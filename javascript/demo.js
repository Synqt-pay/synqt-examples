// The demo's behaviour. Each button shows how to call one part of the SDK; see the README for the full steps.
const {Synqt, Money, IncomingPaymentsApi, isFinal, redirect} = SynqtSDK;

const byId = (id) => document.getElementById(id);
const fieldValue = (id) => byId(id).value.trim();
const log = (message) => (byId('output').textContent = `${new Date().toLocaleTimeString()}  ${message}\n` + byId('output').textContent);

// The return URL must be https (the SDK and the Payment Web App refuse anything else), and on this page's origin for the
// popup to see the payer come back. Served over https, it is prefilled with this folder's return.html; otherwise with a
// placeholder, and the payer closes the popup themselves. Editable like the other fields.
byId('returnURL').value = location.protocol === 'https:' ? new URL('return.html', location.href).href : 'https://example.com/return';

const money = () => new Money(fieldValue('amount'), fieldValue('currencyCode'));

// The order being tested, for the SDK's sheet and the Payment Web App.
const checkout = () => new Synqt(fieldValue('environment')).checkout({
    token: fieldValue('token'),
    payinID: fieldValue('idPayin'),
    money: money(),
    returnURL: fieldValue('returnURL'),
    callbackURL: 'https://example.com/synqt/callback', // your backend in a real integration
});

// SYNQT's payin API with the token on screen, as in the Carpentum Java SDK.
const api = () => IncomingPaymentsApi.create(new Synqt(fieldValue('environment')), fieldValue('token'));

// The payin last paid ({api, id, environment}), so Check status asks about it even if the fields change afterwards. A new token clears it.
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
    const response = await fetch(SynqtSDK.environments[fieldValue('environment')].apiBaseURL + '/auth-tokens', {
        method: 'POST',
        headers: {'Content-Type': 'application/json', Accept: 'application/json', 'X-API-Version': '2'},
        body: JSON.stringify({
            merchantCode: fieldValue('merchantCode'),
            secret: byId('secret').value,
            validitySecs: 1800,
            operations: ['POST /payins/!availablePaymentOptions', `POST /payins/${id}`, `GET /payins/${id}`, 'GET /merchant-info', 'GET /payment-operators'],
            money: money(),
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
    const offered = (await api().payinAvailablePaymentOptions({money: money()})).data ?? [];
    const codes = new Set(offered.map((option) => option.paymentMethodCode));
    const choices = Synqt.directPaymentMethods.filter((method) => codes.has(method.code));
    byId('method').replaceChildren(...choices.map((method) => new Option(method.name, method.code)));
    return `${offered.length} offered, ${choices.length} supported by the sheet: ${choices.map((method) => method.code).join(', ')}`;
}

// Needs a token with GET /payment-operators; a PAYIN_CREATE token does not have it.
action('operators', async () => {
    const ops = await new Synqt(fieldValue('environment')).paymentOperators({token: fieldValue('token')});
    return `${ops.length} payment operators\n` + ops.map((operator) => `${operator.code}  ${operator.name}`).join('\n');
});

async function payWithSheet(checkoutToPay, paymentMethodCode, followed) {
    const result = await checkoutToPay.presentPaymentSheet({
        paymentMethodCode,
        prefill: {
            emailAddress: fieldValue('emailAddress'),
            'customerName.firstName': fieldValue('firstName'),
            'customerName.lastName': fieldValue('lastName')
        },
        onPresented: () => log('Sheet on screen'),
        onPaymentStarted: () => {
            log('Payment sent to SYNQT');
            if (followed) followStatus(followed);
        },
    });
    const next = result && redirect(result);
    if (next?.method === 'GET') window.open(next.url, '_blank');
    return result === null ? 'Sheet closed without paying' : result;
}

action('sheet', () => {
    paid = {api: api(), id: fieldValue('idPayin'), environment: fieldValue('environment')};
    return payWithSheet(checkout(), byId('method').value, paid);
});

// The whole sheet without a token, for trying every method's form.
byId('previewMethod').replaceChildren(...Synqt.directPaymentMethods.map((method) => new Option(method.name, method.code)));
action('preview', () => {
    const previewCheckout = new Synqt(fieldValue('environment')).checkout({
        token: 'preview', payinID: 'preview-1', money: new Money(fieldValue('amount') || '100.00', fieldValue('currencyCode') || 'ZAR'),
        returnURL: fieldValue('returnURL'), callbackURL: 'https://example.com/synqt/callback',
    });
    return payWithSheet(previewCheckout, byId('previewMethod').value);
});

// The Payment Web App has no first or last name parameters, so the name goes as accountName.
action('app', () => {
    paid = {api: api(), id: fieldValue('idPayin'), environment: fieldValue('environment')};
    const prefill = {
        emailAddress: fieldValue('emailAddress'),
        accountName: [fieldValue('firstName'), fieldValue('lastName')].filter(Boolean).join(' '),
    };
    const opened = checkout().presentPaymentApp({
        merchantCode: fieldValue('merchantCode'),
        paymentMethodCode: byId('method').value || undefined,
        prefill: Object.fromEntries(Object.entries(prefill).filter(([, value]) => value)),
        onPresented: () => log('Payment Web App open'),
    });
    followStatus(paid);
    return opened;
});

action('status', async () => {
    const {api: checkedApi, id, environment} = paid ?? {api: api(), id: fieldValue('idPayin'), environment: fieldValue('environment')};
    log(`Checking ${id} on ${environment}`);
    const detail = await checkedApi.getPayin(id);
    showStatus(detail);
    return detail;
});

// The pill shows the payin's status, checked every 5 seconds from the moment a payment is sent until it is final.
let following;
const colours = {SUCCESS: 'green', FAILED: 'crimson', REFUSED: 'crimson', PROCESSING: 'darkorange'};

function showStatus(detail) {
    const status = detail.process?.status ?? 'UNKNOWN';
    byId('pill').textContent = status;
    byId('pill').style.background = colours[status] || 'gray';
}

function followStatus({api: followedApi, id}) {
    clearInterval(following);
    const check = async () => {
        try {
            const detail = await followedApi.getPayin(id);
            showStatus(detail);
            if (isFinal(detail)) clearInterval(following);
        } catch (error) {
            if (error.httpCode === 410) return; // SYNQT has no payin with this ID yet
            log(`Status: ${error.message}`);
            if (error.httpCode) clearInterval(following); // a refusal such as 401 will not fix itself; network errors retry
        }
    };
    following = setInterval(check, 5000);
    check();
}
