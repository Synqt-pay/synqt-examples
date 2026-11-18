package com.synqt.demo

import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Bundle
import android.text.Editable
import android.text.InputType
import android.text.TextWatcher
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.ArrayAdapter
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.RadioButton
import android.widget.RadioGroup
import android.widget.ScrollView
import android.widget.Spinner
import android.widget.TextView
import androidx.activity.ComponentActivity
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.synqt.sdk.CreatePayinResult
import com.synqt.sdk.Money
import com.synqt.sdk.Payin
import com.synqt.sdk.PayinStatus
import com.synqt.sdk.PaymentAppResult
import com.synqt.sdk.PaymentOption
import com.synqt.sdk.Synqt
import com.synqt.sdk.SynqtException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL

// The Payment Web App rejects non-https returnUrls, so the SDK (and WebViewActivity, for redirects) catch this one before it loads.
internal const val RETURN_URL = "https://example.com/synqt/return"

/**
 * What outlives this screen being rebuilt (on rotation, or a dark mode, font size or language switch): the calls in
 * flight, in [viewModelScope] so a rebuild doesn't cancel them (which would close the SDK's sheet), and what they
 * show. The typed fields are restored by Android itself, as they have IDs.
 */
class DemoState : ViewModel() {
    var output = ""
    var pill = "No payin" to Color.GRAY
    var methods: List<PaymentOption> = emptyList()

    // The payin ID a payment was sent for, or the Payment Web App shown for; SYNQT has nothing to report before that.
    var opened = ""
    var following: Job? = null

    /** Draws the state on the current screen; the screen sets it each time it is made. */
    var render: () -> Unit = {}

    fun say(text: String) {
        output = text
        render()
    }
}

/**
 * Test screen. Fields are filled by scripts/sandbox-token.sh via intent extras, or by hand.
 * For merchants without an RSA key yet, a token can be minted here from the (deprecated) Merchant secret key.
 */
class MainActivity : ComponentActivity() {

    private lateinit var state: DemoState
    private lateinit var environments: RadioGroup
    private lateinit var fields: Map<String, EditText>
    private lateinit var secret: EditText
    private lateinit var methodPicker: Spinner
    private lateinit var output: TextView
    private lateinit var pill: TextView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableAddons() // the card add-on in the card variant; adding it again is harmless
        state = ViewModelProvider(this)[DemoState::class.java]
        // Plain platform widgets on purpose, so the SDK's own payment sheet styling stands out.
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(32, 32, 32, 32)
        }
        pill = TextView(this).apply {
            setTextColor(Color.WHITE)
            textSize = 12f
            typeface = Typeface.DEFAULT_BOLD
            setPadding(28, 8, 28, 8)
        }
        root.addView(pill, LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply { bottomMargin = 16 })
        // Fixed IDs, so Android restores what was picked and typed when the screen is rebuilt.
        environments = RadioGroup(this).apply {
            id = 900
            orientation = RadioGroup.HORIZONTAL
            Synqt.Environment.entries.forEach { env ->
                addView(RadioButton(this@MainActivity).apply {
                    id = env.ordinal + 1; text = env.name
                })
            }
            check(Synqt.Environment.SANDBOX.ordinal + 1)
        }
        root.addView(environments)
        fields = KEYS.withIndex().associate { (index, entry) ->
            entry.first to EditText(this).apply { id = 1000 + index; hint = entry.second; setSingleLine() }.also(root::addView)
        }
        fields.getValue("amount").setText("100.00")
        fields.getValue("currencyCode").setText("ZAR")
        fields.getValue("amount").inputType =
            InputType.TYPE_CLASS_NUMBER or InputType.TYPE_NUMBER_FLAG_DECIMAL
        fields.getValue("emailAddress").inputType =
            InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS
        listOf("firstName", "lastName").forEach {
            fields.getValue(it).inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PERSON_NAME or InputType.TYPE_TEXT_FLAG_CAP_WORDS
        }
        secret = EditText(this).apply {
            id = 1100
            hint = "Merchant secret key (only without a private key)"
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD
        }
        root.addView(secret)
        root.addView(action("Get token with secret key") { tokenFromSecret() })
        root.addView(action("Open Payment Web App") { payWithPaymentApp() })
        root.addView(action("Available payment options") { loadOptions() })
        root.addView(action("Payment operators") { paymentOperators() })
        root.addView(TextView(this).apply { text = "Direct API payment method" })
        methodPicker = Spinner(this).apply { id = 1200 }
        showMethods()
        root.addView(methodPicker)
        root.addView(action("Enter details and pay (SDK sheet)") { payWithSheet() })
        root.addView(action("Get status") { payin().status().toString() })
        output = TextView(this).apply { setTextIsSelectable(true) }
        root.addView(output)

        setContentView(ScrollView(this).apply { fitsSystemWindows = true; addView(root) })
        state.render = ::render
        render()
        // A rebuilt screen keeps its calls, pill and fields; only a fresh start reads the launch extras.
        if (savedInstanceState == null) handle(intent)
        // The pill restarts whenever the payin on screen changes. The listeners go on after Android restores the
        // fields, which it does after onCreate, so a half-restored screen doesn't set the pill.
        window.decorView.post {
            followStatus()
            environments.setOnCheckedChangeListener { _, _ -> followStatus() }
            listOf("idPayin", "token").forEach {
                fields.getValue(it).addTextChangedListener(object : TextWatcher {
                    override fun beforeTextChanged(text: CharSequence?, start: Int, count: Int, after: Int) = Unit
                    override fun onTextChanged(text: CharSequence?, start: Int, before: Int, count: Int) = Unit
                    override fun afterTextChanged(text: Editable?) = followStatus()
                })
            }
        }
    }

    override fun onDestroy() {
        state.render = {} // the next screen sets its own
        super.onDestroy()
    }

    private fun render() {
        output.text = state.output
        val (text, color) = state.pill
        pill.text = text
        pill.background = GradientDrawable().apply { setColor(color); cornerRadius = 999f }
        pill.contentDescription = "Payment status: $text"
    }

    // These run in the ViewModel's scope, so they outlive this screen; they report through state, never its views.

    private suspend fun payWithSheet(): String {
        val method = state.methods.getOrNull(methodPicker.selectedItemPosition)?.code
            ?: throw IllegalArgumentException("No payment method yet. Tap \"Available payment options\" first.")
        val payin = payin()
        val sheetResult = payin.presentPaymentSheet(this, method, prefill(),
            onPresented = { state.say("Payment sheet on screen.") },
            onPaymentStarted = {
                opened(payin.id)
                state.say("Payment sent to SYNQT.")
            })
            ?: return "Payment form closed without paying.\n\n${latestStatus(payin)}"
        val result = when (sheetResult) {
            is CreatePayinResult.Redirect -> {
                if (sheetResult.httpMethod == "GET") openInWebView(sheetResult.url)
                "Redirect ${sheetResult.httpMethod} ${sheetResult.url}\n${sheetResult.formData}"
            }

            is CreatePayinResult.Instructions -> sheetResult.paymentMethod.toString()
        }
        return "${latestStatus(payin)}\n\n$result"
    }

    private suspend fun payWithPaymentApp(): String {
        val payin = payin()
        // The web app has no first or last name parameter; accountName is the closest. A method from the dropdown
        // is preselected, and optionsAvailable lets the payer pick another. allowCustomerDataChange keeps the details editable.
        val name = listOf(value("firstName"), value("lastName")).filter { it.isNotEmpty() }.joinToString(" ")
        val extra = mapOf(
            "emailAddress" to value("emailAddress"),
            "accountName" to name,
            "paymentMethodCode" to (state.methods.getOrNull(methodPicker.selectedItemPosition)?.code ?: ""),
        ).filterValues { it.isNotEmpty() } + mapOf("allowCustomerDataChange" to "true", "optionsAvailable" to "true")
        val appResult = payin.presentPaymentApp(this, value("merchantCode"), extra,
            onPresented = {
                opened(payin.id)
                state.say("Payment Web App on screen.")
            })
        val how = if (appResult == PaymentAppResult.Closed) "Payment Web App closed by the payer." else "Payment Web App returned to the app."
        return "$how\n\n${latestStatus(payin)}"
    }

    private fun opened(id: String) {
        state.opened = id
        followStatus()
    }

    /** Keeps the status pill current: every 5 seconds until the status can no longer change. */
    private fun followStatus() {
        state.following?.cancel()
        val payin = runCatching { payin() }.getOrNull()?.takeIf { value("idPayin").isNotEmpty() && value("token").isNotEmpty() }
        state.following = state.viewModelScope.launch {
            fun show(text: String, color: Int) {
                state.pill = text to color
                state.render()
            }
            if (payin == null) return@launch show("No payin", Color.GRAY)
            if (state.opened != payin.id) return@launch show("Not started", Color.GRAY)
            while (true) {
                try {
                    val status = payin.status().status
                    show(status.name, when (status) {
                        PayinStatus.Status.SUCCESS -> Color.rgb(46, 125, 50)
                        PayinStatus.Status.FAILED, PayinStatus.Status.REFUSED -> Color.rgb(198, 40, 40)
                        PayinStatus.Status.PROCESSING -> Color.rgb(230, 81, 0)
                        else -> Color.GRAY
                    })
                    if (status.isFinal) return@launch
                } catch (error: SynqtException) {
                    // SYNQT answers 410 Gone for a payin ID it doesn't have: the Payment Web App before Pay, or a refused payment.
                    if (error.httpCode == 410) show("Not started", Color.GRAY) else show("HTTP ${error.httpCode}", Color.GRAY)
                } catch (error: IOException) {
                    show("Offline", Color.GRAY)
                }
                delay(5_000)
            }
        }
    }

    /** Where the payin stands once the sheet closes. For display only: an order is paid when the backend says so. */
    private suspend fun latestStatus(payin: Payin) = try {
        val payinStatus = payin.status()
        "Status: ${payinStatus.status}" + (payinStatus.failureReason?.let { "\n${it.payerMessage(this@MainActivity)} (${it.code})" }
            .orEmpty())
    } catch (error: SynqtException) {
        "Status unavailable: HTTP ${error.httpCode} " + error.errors.joinToString { it.code }
    } catch (error: IOException) {
        "Status unavailable: could not reach SYNQT"
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handle(intent)
    }

    private fun handle(intent: Intent) {
        intent.getStringExtra("environment")
            ?.let { environments.check(Synqt.Environment.valueOf(it.uppercase()).ordinal + 1) }
        KEYS.forEach { (key) ->
            intent.getStringExtra(key)?.let { fields.getValue(key).setText(it) }
        }
        if (intent.dataString?.startsWith(RETURN_URL) == true) run { payin().status().toString() } // back from a direct-API redirect
        // For screenshots without a token: `adb shell am start -n com.synqt.demo/.MainActivity --es sheet CAPITEC_PAY`
        // opens the sheet at once. Paying then fails with SYNQT's 401, shown in the sheet.
        intent.getStringExtra("sheet")?.let { code ->
            fields.getValue("idPayin").setText("preview-1")
            fields.getValue("token").setText("preview")
            run { payin().presentPaymentSheet(this, code, prefill())?.toString() ?: "Payment form closed without paying." }
        }
    }

    private fun openInWebView(url: String) =
        startActivity(Intent(this, WebViewActivity::class.java).setData(Uri.parse(url)))

    private fun environment() = Synqt.Environment.entries[environments.checkedRadioButtonId - 1]

    /** The order being tested, from the fields on screen. */
    private fun payin() = Synqt(environment()).payin(
        value("token"),
        value("idPayin"),
        Money(
            amount(),
            value("currencyCode")
        ),
        RETURN_URL,
        CALLBACK_URL,
    )

    /** What the SDK sheet fills in for the payer, keyed by field path. */
    private fun prefill() = mapOf(
        "emailAddress" to value("emailAddress"),
        "customerName.firstName" to value("firstName"),
        "customerName.lastName" to value("lastName"),
    ).filterValues { it.isNotEmpty() }

    /** Fills the method dropdown with what SYNQT offers for this payin. A null name means the SDK sheet can't show it. */
    private suspend fun loadOptions(): String {
        val options = payin().availablePaymentOptions()
        state.methods = options.filter { it.name(this) != null }
        showMethods()
        return "${state.methods.size} of ${options.size} offered methods can use the SDK sheet\n\n" + options.joinToString(
            "\n"
        )
    }

    private fun showMethods() {
        methodPicker.adapter = ArrayAdapter(
            this,
            android.R.layout.simple_spinner_dropdown_item,
            state.methods.map { it.name(this) })
    }

    /** Needs a token with GET /payment-operators: the secret-key button asks for it, a PAYIN_CREATE token does not have it. */
    private suspend fun paymentOperators(): String = try {
        val operators = Synqt(environment()).paymentOperators(value("token"))
        "${operators.size} payment operators\n\n" + operators.joinToString("\n") { op ->
            val providers = op.externalProviders.joinToString { "${it.code} (${it.name})" }
            "${op.code}  ${op.name}" + if (providers.isEmpty()) "" else "\n    providers: $providers"
        }
    } catch (error: SynqtException) {
        if (error.httpCode != 403) throw error
        "HTTP 403: this token cannot list payment operators. Use \"Get token with secret key\", which asks for GET /payment-operators."
    }

    /** Same request as the WordPress plugin's secret fallback: POST /auth-tokens scoped to one payin, plus GET /payment-operators. */
    private suspend fun tokenFromSecret(): String {
        // A payin ID is used once, so every token gets a fresh one; reusing it would return the earlier attempt.
        fields.getValue("idPayin").setText("test-${System.currentTimeMillis()}")
        val id = value("idPayin")
        val operations = listOf(
            "POST /payins/!availablePaymentOptions",
            "POST /payins/$id",
            "GET /payins/$id",
            "GET /merchant-info",
            "GET /payment-operators"
        )
        val body = JSONObject()
            .put("merchantCode", value("merchantCode"))
            .put("secret", secret.text.toString())
            .put("validitySecs", 1800)
            .put("operations", JSONArray(operations))
            .put("money", money())
        fields.getValue("token")
            .setText(post(environment().apiBaseUrl + "/auth-tokens", body).getString("token"))
        val options = try {
            loadOptions()
        } catch (error: Exception) {
            "Could not load payment options: $error"
        }
        return "Token issued for $id on ${environment()}\n\n$options"
    }

    // Kept out of the SDK on purpose: a merchant secret must never ship in a real app.
    private suspend fun post(url: String, body: JSONObject) = withContext(Dispatchers.IO) {
        val conn = URL(url).openConnection() as HttpURLConnection
        try {
            conn.requestMethod = "POST"
            conn.doOutput = true
            conn.setRequestProperty("Accept", "application/json")
            conn.setRequestProperty("Content-Type", "application/json")
            conn.setRequestProperty("X-API-Version", "2")
            conn.outputStream.use { it.write(body.toString().toByteArray()) }
            val code = conn.responseCode
            val stream = if (code < 400) conn.inputStream else conn.errorStream
            val text = stream?.bufferedReader()?.use { it.readText() }.orEmpty()
            if (code !in 200..299) throw IOException("Token request failed: HTTP $code\n$text") // test screen only
            JSONObject(text)
        } finally {
            conn.disconnect()
        }
    }

    private fun action(label: String, block: suspend () -> String) = Button(this).apply {
        text = label
        setOnClickListener { run(block) }
    }

    /** Runs [block] in the ViewModel's scope, so a rebuilt screen neither cancels it nor misses its result. */
    private fun run(block: suspend () -> String) {
        state.say("…")
        state.viewModelScope.launch {
            state.say(
                try {
                    block()
                } catch (error: SynqtException) {
                    "HTTP ${error.httpCode}\n" + error.errors.joinToString("\n")
                } catch (error: Exception) {
                    // Form checks (missing field, bad number) carry a readable message; anything else shows its type.
                    (error as? IllegalArgumentException)?.message ?: error.toString()
                }
            )
        }
    }

    private fun value(key: String) = fields.getValue(key).text.toString().trim()

    private fun amount() = value("amount").toBigDecimalOrNull()
        ?: throw IllegalArgumentException("Amount must be a number, for example 100.00")

    private fun money() =
        JSONObject().put("amount", amount()).put("currencyCode", value("currencyCode"))

    private companion object {
        // Intent extra name to label.
        val KEYS = listOf(
            "merchantCode" to "Merchant code", "idPayin" to "Payin ID", "token" to "Token",
            "amount" to "Amount", "currencyCode" to "Currency", "emailAddress" to "Customer email",
            "firstName" to "Customer first name", "lastName" to "Customer last name",
        )
        const val CALLBACK_URL =
            "https://example.com/synqt/callback" // nothing listens; fine for testing
    }
}
