// The demo's behaviour. Each button shows how to call one part of the SDK; see the README for the full steps.
const {Synqt, Money} = SynqtSDK;

const byId = (id) => document.getElementById(id);
const fieldValue = (id) => byId(id).value.trim();
const log = (message) => (byId('output').textContent = `${new Date().toLocaleTimeString()}  ${message}\n` + byId('output').textContent);

// The return URL must be https (the SDK and the Payment Web App refuse anything else), and on this page's origin for the
// popup to see the payer come back. Prefilled with this folder's return.html: here if the page is served over https,
// else where scripts/serve-https.sh serves it. Editable like the other fields.
byId('returnURL').value = location.protocol === 'https:'
    ? new URL('return.html', location.href).href
    : 'https://localhost:8443/' + new URL('return.html', location.href).pathname.split('/').slice(-3).join('/');

const payin = () => new Synqt(fieldValue('environment')).payin({
    token: fieldValue('token'),
    payinID: fieldValue('idPayin'),
    money: new Money(fieldValue('amount'), fieldValue('currencyCode')),
    returnURL: fieldValue('returnURL'),
    callbackURL: 'https://example.com/synqt/callback', // your backend in a real integration
});

// The payin last paid, so Check status asks about it even if the fields change afterwards. A new token clears it.
let paid;

// Every button reports its result or error in the output area.
const action = (id, run) => byId(id).addEventListener('click', async () => {
    try {
        const out = await run();
        if (out !== undefined) log(typeof out === 'string' ? out : JSON.stringify(out, null, 2));
    } catch (error) {
        log(`${error.name}: ${error.message}`);
    }
});

action('usePaste', () => {
    const pasted = JSON.parse(fieldValue('paste'));
    for (const field of ['environment', 'merchantCode', 'idPayin', 'token', 'amount', 'currencyCode']) if (pasted[field]) byId(field).value = pasted[field];
    paid = undefined;
    return `Using payin ${pasted.idPayin}`;
});

// For merchants without an RSA key yet. SYNQT has deprecated the secret key, and it must never be in a real page: a
// real integration mints tokens on its backend (README step 2). The token also allows the merchant name and the
// payment operator list.
action('tokenFromSecret', async () => {
    // A payin ID is used once, so every token gets a fresh one; reusing it would return the earlier attempt.
    const id = `test-${Date.now()}`;
    byId('idPayin').value = id;
    paid = undefined;
    const money = new Money(fieldValue('amount'), fieldValue('currencyCode'));
    const response = await fetch(SynqtSDK.environments[fieldValue('environment')].apiBaseURL + '/auth-tokens', {
        method: 'POST',
        headers: {'Content-Type': 'application/json', Accept: 'application/json', 'X-API-Version': '2'},
        body: JSON.stringify({
            merchantCode: fieldValue('merchantCode'),
            secret: byId('secret').value,
            validitySecs: 1800,
            operations: ['POST /payins/!availablePaymentOptions', `POST /payins/${id}`, `GET /payins/${id}`, 'GET /merchant-info', 'GET /payment-operators'],
            money,
        }),
    });
    const body = await response.text();
    let token;
    try {
        token = JSON.parse(body).token;
    } catch {
        // Not JSON: the error below shows the raw body.
    }
    if (!response.ok || !token) throw new Error(`Token request failed: HTTP ${response.status}\n${body}`); // test page only
    byId('token').value = token;
    return `Token issued for ${id} on ${fieldValue('environment')}\n\n${await loadOptions().catch((error) => `Could not load payment options: ${error.message}`)}`;
});

action('options', () => loadOptions());

async function loadOptions() {
    const offered = await payin().availablePaymentOptions();
    const supported = new Set(Synqt.directPaymentMethods.map((method) => method.code));
    const choices = offered.filter((option) => supported.has(option.code));
    byId('method').replaceChildren(...choices.map((option) => new Option(option.name, option.code)));
    return `${offered.length} offered, ${choices.length} supported by the sheet: ${choices.map((option) => option.code).join(', ')}`;
}

// Needs a token with GET /payment-operators; a PAYIN_CREATE token does not have it.
action('operators', async () => {
    const ops = await new Synqt(fieldValue('environment')).paymentOperators({token: fieldValue('token')});
    return `${ops.length} payment operators\n` + ops.map((operator) => `${operator.code}  ${operator.name}`).join('\n');
});

async function payWithSheet(payinToPay, paymentMethodCode) {
    const result = await payinToPay.presentPaymentSheet({
        paymentMethodCode,
        prefill: {
            emailAddress: fieldValue('emailAddress'),
            'customerName.firstName': fieldValue('firstName'),
            'customerName.lastName': fieldValue('lastName')
        },
        onPresented: () => log('Sheet on screen'),
        onPaymentStarted: () => {
            log('Payment sent to SYNQT');
            followStatus(payinToPay);
        },
    });
    if (result && result.type === 'redirect' && result.httpMethod === 'GET') window.open(result.url, '_blank');
    return result === null ? 'Sheet closed without paying' : result;
}

action('sheet', () => {
    paid = {payin: payin(), environment: fieldValue('environment')};
    return payWithSheet(paid.payin, byId('method').value);
});

// The whole sheet without a token, for trying every method's form.
byId('previewMethod').replaceChildren(...Synqt.directPaymentMethods.map((method) => new Option(method.name, method.code)));
action('preview', () => {
    const previewPayin = new Synqt(fieldValue('environment')).payin({
        token: 'preview', payinID: 'preview-1', money: new Money(fieldValue('amount') || '100.00', fieldValue('currencyCode') || 'ZAR'),
        returnURL: fieldValue('returnURL'), callbackURL: 'https://example.com/synqt/callback',
    });
    return payWithSheet(previewPayin, byId('previewMethod').value);
});

// The Payment Web App has no first or last name parameters, so the name goes as accountName.
action('app', () => {
    paid = {payin: payin(), environment: fieldValue('environment')};
    const appPayin = paid.payin;
    const prefill = {
        emailAddress: fieldValue('emailAddress'),
        accountName: [fieldValue('firstName'), fieldValue('lastName')].filter(Boolean).join(' '),
    };
    const opened = appPayin.presentPaymentApp({
        merchantCode: fieldValue('merchantCode'),
        paymentMethodCode: byId('method').value || undefined,
        prefill: Object.fromEntries(Object.entries(prefill).filter(([, value]) => value)),
        onPresented: () => log('Payment Web App open'),
    });
    followStatus(appPayin);
    return opened;
});

action('status', async () => {
    const {payin: checkedPayin, environment} = paid ?? {payin: payin(), environment: fieldValue('environment')};
    log(`Checking ${checkedPayin.id} on ${environment}`);
    const status = await checkedPayin.status();
    showStatus(status);
    return status;
});

// The pill shows the payin's status, checked every 5 seconds from the moment a payment is sent until it is final.
let following;
const colours = {SUCCESS: 'green', FAILED: 'crimson', REFUSED: 'crimson', PROCESSING: 'darkorange'};

function showStatus(payinStatus) {
    byId('pill').textContent = payinStatus.status;
    byId('pill').style.background = colours[payinStatus.status] || 'gray';
}

function followStatus(followedPayin) {
    clearInterval(following);
    const check = async () => {
        try {
            const payinStatus = await followedPayin.status();
            showStatus(payinStatus);
            if (payinStatus.isFinal) clearInterval(following);
        } catch (error) {
            if (error.httpCode === 410) return; // SYNQT has no payin with this ID yet
            log(`Status: ${error.message}`);
            if (error.httpCode) clearInterval(following); // a refusal such as 401 will not fix itself; network errors retry
        }
    };
    following = setInterval(check, 5000);
    check();
}
