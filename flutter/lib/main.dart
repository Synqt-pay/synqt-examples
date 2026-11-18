import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:synqt/synqt.dart';
import 'package:url_launcher/url_launcher.dart';

// The Payment Web App rejects non-https returnUrls; presentPaymentApp catches this one before it loads.
const returnUrl = 'https://example.com/synqt/return';
const callbackUrl = 'https://example.com/synqt/callback'; // nothing listens; fine for testing

void main() => runDemo();

/// Starts the demo. Card mode (`card/main.dart`) enables the card add-on first, then calls this.
void runDemo() => runApp(const MaterialApp(title: 'Synqt Demo', home: DemoPage()));

/// Test screen. Fields are filled by scripts/sandbox-token.sh (Paste from script), or by hand. For merchants without
/// an RSA key yet, a token can be minted here from the (deprecated) merchant secret key. Plain Material controls on
/// purpose, so the SDK's own payment sheet styling stands out.
class DemoPage extends StatefulWidget {
  const DemoPage({super.key});

  @override
  State<DemoPage> createState() => _DemoPageState();
}

class _DemoPageState extends State<DemoPage> {
  var _environment = SynqtEnvironment.sandbox;
  final _fields = {
    for (final key in [
      'merchantCode',
      'idPayin',
      'token',
      'amount',
      'currencyCode',
      'emailAddress',
      'firstName',
      'lastName',
      'secret',
    ])
      key: TextEditingController(),
  };
  // Filled from the payin's own options; empty until they are fetched.
  var _methods = <PaymentOption>[];
  String? _method;
  var _output = '';
  var _pill = ('No payin', Colors.grey);
  Timer? _poll;

  static const _labels = {
    'merchantCode': 'Merchant code',
    'idPayin': 'Payin ID',
    'token': 'Token',
    'amount': 'Amount',
    'currencyCode': 'Currency',
    'emailAddress': 'Customer email',
    'firstName': 'Customer first name',
    'lastName': 'Customer last name',
    'secret': 'Merchant secret key (only without a private key)',
  };

  @override
  void initState() {
    super.initState();
    _fields['amount']!.text = '100.00';
    _fields['currencyCode']!.text = 'ZAR';
  }

  @override
  void dispose() {
    _poll?.cancel();
    for (final controller in _fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String _value(String key) => _fields[key]!.text.trim();

  /// The order being tested, from the fields on screen.
  Payin _payin() => Synqt(_environment).payin(
    token: _value('token'),
    payinId: _value('idPayin'),
    money: Money(amount: _value('amount'), currencyCode: _value('currencyCode')),
    returnUrl: returnUrl,
    callbackUrl: callbackUrl,
  );

  /// What the SDK sheet fills in for the payer, keyed by field path.
  Map<String, String> _prefill() => {
    'emailAddress': _value('emailAddress'),
    'customerName.firstName': _value('firstName'),
    'customerName.lastName': _value('lastName'),
  }..removeWhere((_, value) => value.isEmpty);

  Future<String> _payWithSheet() async {
    final method = _method;
    if (method == null) return 'No payment method yet. Tap "Available payment options" first.';
    final payin = _payin();
    final sheetResult = await payin.presentPaymentSheet(
      context,
      paymentMethodCode: method,
      prefill: _prefill(),
      onPresented: () => setState(() => _output = 'Payment sheet on screen.'),
      onPaymentStarted: () {
        setState(() => _output = 'Payment sent to SYNQT.');
        _followStatus(payin);
      },
    );
    switch (sheetResult) {
      case null:
        return 'Payment sheet closed without paying.\n\n${await _latestStatus(payin)}';
      case RedirectResult(:final httpMethod, :final url, :final formData):
        // A direct-API GET redirect (bank login and the like) opens in the browser here.
        if (httpMethod == 'GET') unawaited(launchUrl(Uri.parse(url)));
        return '${await _latestStatus(payin)}\n\nRedirect $httpMethod $url\n$formData';
      case InstructionsResult(:final paymentMethod):
        return '${await _latestStatus(payin)}\n\n$paymentMethod';
    }
  }

  Future<String> _payWithPaymentApp() async {
    final payin = _payin();
    // The Payment Web App has no first or last name parameter; accountName takes the full name.
    final prefill = {
      'emailAddress': _value('emailAddress'),
      'accountName': [_value('firstName'), _value('lastName')].where((name) => name.isNotEmpty).join(' '),
    }..removeWhere((_, value) => value.isEmpty);
    final result = await payin.presentPaymentApp(
      context,
      merchantCode: _value('merchantCode'),
      paymentMethodCode: _method, // opens on the picked method, if any; the payer can still choose another
      prefill: prefill,
      onPresented: () {
        setState(() => _output = 'Payment Web App on screen.');
        _followStatus(payin);
      },
    );
    final how = result is PaymentAppClosed
        ? 'Payment Web App closed by the payer.'
        : 'Payment Web App returned to the app.';
    return '$how\n\n${await _latestStatus(payin)}';
  }

  /// Keeps the status pill current: every 5 seconds until the status can no longer change.
  void _followStatus(Payin payin) {
    _poll?.cancel();
    Future<void> check() async {
      try {
        final status = (await payin.status()).status;
        if (!mounted) return;
        setState(
          () => _pill = (
            status.code,
            switch (status) {
              PayinState.success => Colors.green,
              PayinState.failed || PayinState.refused => Colors.red,
              PayinState.processing => Colors.orange,
              PayinState.unknown => Colors.grey,
            },
          ),
        );
        if (status.isFinal) _poll?.cancel();
      } on SynqtApiException catch (error) {
        // SYNQT answers 410 Gone for a payin ID it doesn't have: the Payment Web App before Pay, or a refused payment.
        if (mounted) setState(() => _pill = (error.httpCode == 410 ? 'Not started' : 'HTTP ${error.httpCode}', Colors.grey));
      } on Exception {
        if (mounted) setState(() => _pill = ('Offline', Colors.grey));
      }
    }

    unawaited(check());
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => unawaited(check()));
  }

  /// Where the payin stands once the sheet closes. For display only: an order is paid when the backend says so.
  Future<String> _latestStatus(Payin payin) async {
    try {
      final payinStatus = await payin.status();
      final failure = payinStatus.failureReason;
      return 'Status: ${payinStatus.status.code}${failure == null ? '' : '\n${failure.payerMessage} (${failure.code})'}';
    } on SynqtApiException catch (error) {
      return 'Status unavailable: HTTP ${error.httpCode} ${error.errors.map((apiError) => apiError.code).join(', ')}';
    } on Exception {
      return 'Status unavailable: could not reach SYNQT';
    }
  }

  /// Fills the method picker with what SYNQT offers for this payin. A null name means the SDK sheet can't show it.
  Future<String> _loadOptions() async {
    final options = await _payin().availablePaymentOptions();
    setState(() {
      _methods = options.where((option) => option.name != null).toList();
      _method = _methods.firstOrNull?.code;
    });
    return '${_methods.length} of ${options.length} offered methods can use the SDK sheet\n\n${options.join('\n')}';
  }

  /// Needs a token with GET /payment-operators: the secret-key button asks for it, a PAYIN_CREATE token does not have it.
  Future<String> _paymentOperators() async {
    try {
      final operators = await Synqt(_environment).paymentOperators(token: _value('token'));
      return '${operators.length} payment operators\n\n${operators.map((op) {
        final providers = op.externalProviders.map((provider) => '${provider.code} (${provider.name})').join(', ');
        return '${op.code}  ${op.name}${providers.isEmpty ? '' : '\n    providers: $providers'}';
      }).join('\n')}';
    } on SynqtApiException catch (error) {
      if (error.httpCode != 403) rethrow;
      return 'HTTP 403: this token cannot list payment operators. Use "Get token with secret key", which asks for GET /payment-operators.';
    }
  }

  /// Same request as the WordPress plugin's secret fallback: POST /auth-tokens scoped to one payin, plus GET
  /// /payment-operators. Kept out of the SDK on purpose: a merchant secret must never ship in a real app.
  Future<String> _tokenFromSecret() async {
    // A payin ID is used once, so every token gets a fresh one; reusing it would return the earlier attempt.
    final id = 'test-${DateTime.now().millisecondsSinceEpoch}';
    _fields['idPayin']!.text = id;
    final money = _payin().money;
    final response = await http.post(
      Uri.parse('${_environment.apiBaseUrl}/auth-tokens'),
      headers: {'Content-Type': 'application/json', 'Accept': 'application/json', 'X-API-Version': '2'},
      body: jsonEncode({
        'merchantCode': _value('merchantCode'),
        'secret': _value('secret'),
        'validitySecs': 1800,
        'operations': [
          'POST /payins/!availablePaymentOptions',
          'POST /payins/$id',
          'GET /payins/$id',
          'GET /merchant-info',
          'GET /payment-operators',
        ],
        'money': money.toJson(),
      }),
    );
    final token = response.statusCode == 200 ? (jsonDecode(response.body) as Map)['token'] as String? : null;
    if (token == null) return 'Token request failed: HTTP ${response.statusCode}\n${response.body}'; // test screen only
    _fields['token']!.text = token;
    final options = await _loadOptions().catchError((_) => 'Could not load payment options');
    return 'Token issued for $id on ${_environment.name}\n\n$options';
  }

  /// scripts/sandbox-token.sh copies its values as JSON; the iOS Simulator shares the Mac's clipboard.
  Future<String> _pasteFromScript() async {
    final data = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    Map<String, Object?>? values;
    try {
      values = jsonDecode(data ?? '') as Map<String, Object?>;
    } on Object {
      return 'The clipboard holds no values from scripts/sandbox-token.sh.';
    }
    setState(() {
      _environment = SynqtEnvironment.values.where((environment) => environment.name == values!['environment']).firstOrNull ?? _environment;
      for (final entry in values!.entries) {
        if (_fields.containsKey(entry.key) && entry.value is String) _fields[entry.key]!.text = entry.value! as String;
      }
    });
    return 'Pasted ${values.keys.toList()..sort()}';
  }

  void _run(Future<String> Function() block) {
    setState(() => _output = '…');
    block().then(
      (message) {
        if (mounted) setState(() => _output = message);
      },
      onError: (Object error) {
        if (mounted) {
          setState(
            () => _output = error is SynqtApiException
                ? 'HTTP ${error.httpCode}\n${error.errors.map((apiError) => '${apiError.code} ${apiError.field ?? ''} ${apiError.description ?? ''}').join('\n')}'
                : '$error',
          );
        }
      },
    );
  }

  Widget _action(String label, Future<String> Function() block) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: OutlinedButton(onPressed: () => _run(block), child: Text(label)),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Synqt Demo'),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Semantics(
            label: 'Payment status: ${_pill.$1}',
            child: Chip(label: Text(_pill.$1), backgroundColor: _pill.$2),
          ),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SegmentedButton<SynqtEnvironment>(
          showSelectedIcon: false, // the check mark makes SANDBOX wrap on narrow phones
          segments: [
            for (final environment in SynqtEnvironment.values) ButtonSegment(value: environment, label: Text(environment.name.toUpperCase())),
          ],
          selected: {_environment},
          onSelectionChanged: (selection) => setState(() => _environment = selection.first),
        ),
        const SizedBox(height: 8),
        for (final entry in _fields.entries)
          TextField(
            controller: entry.value,
            decoration: InputDecoration(labelText: _labels[entry.key]),
            obscureText: entry.key == 'secret',
            autocorrect: false,
          ),
        const SizedBox(height: 16),
        _action('Paste from script', _pasteFromScript),
        _action('Get token with secret key', _tokenFromSecret),
        _action('Open Payment Web App', _payWithPaymentApp),
        _action('Available payment options', _loadOptions),
        _action('Payment operators', _paymentOperators),
        const SizedBox(height: 8),
        DropdownButton<String>(
          isExpanded: true,
          hint: const Text('Method'),
          value: _method,
          items: [for (final method in _methods) DropdownMenuItem(value: method.code, child: Text(method.name ?? method.code))],
          onChanged: (code) => setState(() => _method = code),
        ),
        _action('Enter details and pay (SDK sheet)', _payWithSheet),
        _action('Get status', () async => '${await _payin().status()}'),
        SelectableText(_output, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
      ],
    ),
  );
}
