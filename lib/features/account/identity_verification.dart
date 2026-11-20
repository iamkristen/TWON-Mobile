import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/models.dart';
import '../../shared/widgets.dart';

/// IV-E2E: identity verification on the phone, through the backend's IV4
/// capture sessions (`verification/sessions`).
///
/// - Every photo is taken with the CAMERA (no gallery in this flow): the live
///   selfie and the photo holding the document use the front camera, documents
///   the rear camera. Liveness here means a live capture reviewed by a person;
///   there is no automatic face matching and no automatic approval.
/// - Previews are shown from the local file only (the server never returns an
///   image) and the files are deleted after submitting or cancelling.
/// - The steps come from the server (never hard-coded), so the policy can ask
///   for the back of a document or a holding photo.
/// - The verified badge is never inferred from the case state.

/// Member-facing copy for each case state (unknown states count as "under review").
({String title, String body}) identityStateCopy(String state) => switch (state) {
  'none' => (title: 'Not verified', body: 'Verify your identity with your passport or an accepted national ID, using this phone\'s camera.'),
  'submitted' || 'under_review' || 'escalated' => (title: 'Under review', body: 'A reviewer is checking your verification. We\'ll update this page when there is a decision.'),
  'more_evidence_required' => (title: 'More evidence needed', body: 'The reviewer needs more photos before deciding.'),
  'approved' => (title: 'Verified', body: 'Your identity has been verified.'),
  'rejected' => (title: 'Not verified', body: 'Your verification was not approved.'),
  'appealed' => (title: 'Appeal under review', body: 'A different reviewer is looking at your appeal.'),
  'suspended' => (title: 'Verification paused', body: 'Your verification is paused while our team reviews a change. No action is needed.'),
  'revoked' => (title: 'Verification withdrawn', body: 'Your verification has been withdrawn.'),
  'expired' => (title: 'Verification expired', body: 'Your verification has expired. You can verify again.'),
  'closed' => (title: 'Closed', body: 'This verification is closed.'),
  _ => (title: 'Under review', body: 'Your verification is being processed.'),
};

/// Plain-language reasons for decision codes (staff notes are never shown).
String identityReasonCopy(String? code) => switch (code) {
  'document_not_accepted' => 'This document type is not accepted for verification.',
  'document_expired' => 'The document has expired.',
  'document_unreadable' => 'The document could not be read clearly.',
  'tampering_suspected' => 'The document could not be accepted.',
  'holder_mismatch' => 'The photos did not show the document holder clearly.',
  'name_mismatch' => 'The name on the document does not match your profile name.',
  'account_ineligible' => 'This account cannot be verified at the moment.',
  'duplicate_identity' => 'This identity is already linked to another account.',
  'image_unreadable' || 'glare_or_blur' => 'A photo was blurred or had glare.',
  'missing_side' => 'A side of the document is missing.',
  'holding_photo_required' => 'A photo of you holding the document is needed.',
  'fraud_confirmed' || 'document_invalidated' => 'The verification could not be kept.',
  'member_request' => 'Withdrawn at your request.',
  _ => 'See the help centre for more information.',
};

/// What each capture step asks for, and which camera it uses.
({String title, String hint, bool front}) identityStepCopy(String kind) => switch (kind) {
  'document_front' => (title: 'Front of your document', hint: 'Place the document on a flat surface in good light. All four corners must be visible.', front: false),
  'document_back' => (title: 'Back of your document', hint: 'Turn the document over and photograph the back.', front: false),
  'selfie' => (title: 'Live selfie', hint: 'Look straight at the camera, face uncovered, no filters. The photo is taken live.', front: true),
  'holding_document' => (title: 'You holding your document', hint: 'Hold the document next to your face so both are clearly visible.', front: true),
  _ => (title: kind, hint: '', front: false),
};

class IdentityVerificationPage extends StatelessWidget {
  const IdentityVerificationPage({super.key});

  @override
  Widget build(BuildContext c) => DetailView(
    path: 'verification/status',
    builder: (context, status, refresh) {
      final request = status.object('request');
      final state = request.isEmpty ? 'none' : (request['state']?.toString() ?? 'under_review');
      final copy = identityStateCopy(state);
      final appealableUntil = request['appealableUntil']?.toString();
      final requested = (request['requestedKinds'] as List?)?.map((e) => '$e').toList() ?? const <String>[];
      // A new verification can start when nothing is open (a revoked one only once its appeal window has passed).
      final canStart = ['none', 'rejected', 'expired', 'closed'].contains(state) || (state == 'revoked' && appealableUntil == null);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeading('Identity verification', copy.title),
          Text(copy.body, key: const Key('identity-state-body')),
          if (['rejected', 'revoked'].contains(state) && request['reasonCode'] != null) ...[
            const SizedBox(height: 8),
            Text(identityReasonCopy(request['reasonCode']?.toString()), key: const Key('identity-reason')),
          ],
          if (state == 'more_evidence_required' && requested.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Requested: ${requested.map((k) => identityStepCopy(k).title).join(', ')}'),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => _start(context, const {}),
              child: const Text('Add the requested photos'),
            ),
          ],
          if (appealableUntil != null) ...[
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => _appeal(context, '${request['_id'] ?? request['id']}', refresh),
              child: const Text('Appeal this decision'),
            ),
          ],
          if (canStart) ...[
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => _chooseDocument(context),
              child: Text(state == 'none' ? 'Verify with this phone' : 'Verify again'),
            ),
          ],
          if (canStart || state == 'more_evidence_required') ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => _enterCode(context),
              child: const Text('I have a code from the TWON website'),
            ),
          ],
          const SizedBox(height: 16),
          Text(
            'Photos are taken with your camera and checked by trained reviewers. They are encrypted and never shown publicly.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      );
    },
  );

  static Future<void> _start(BuildContext c, Json body) async {
    try {
      final session = asJson(await repository(c).request('verification/sessions', method: 'POST', body: body));
      if (c.mounted) await c.push('/verification/capture', extra: session);
    } on AppFailure catch (e) {
      if (c.mounted) notice(c, e.message);
    }
  }

  static Future<void> _chooseDocument(BuildContext c) async {
    final choice = await showModalBottomSheet<Json>(context: c, builder: (_) => const _DocumentChoice());
    if (choice != null && c.mounted) await _start(c, choice);
  }

  static Future<void> _enterCode(BuildContext c) async {
    final code = await showDialog<String>(context: c, builder: (_) => const _CodeDialog());
    if (code != null && c.mounted) await c.push('/identity/pair', extra: {'code': code});
  }

  static Future<void> _appeal(BuildContext c, String requestId, VoidCallback refresh) async {
    final statement = await showDialog<String>(context: c, builder: (_) => const _AppealDialog());
    if (statement == null || !c.mounted) return;
    try {
      await repository(c).request('verification/appeals', method: 'POST', body: {'requestId': requestId, 'statement': statement});
      if (c.mounted) notice(c, 'Appeal sent. A different reviewer will look at it.');
      refresh();
    } on AppFailure catch (e) {
      if (c.mounted) notice(c, e.message);
    }
  }
}

class _DocumentChoice extends StatefulWidget {
  const _DocumentChoice();
  @override
  State<_DocumentChoice> createState() => _DocumentChoiceState();
}

class _DocumentChoiceState extends State<_DocumentChoice> {
  String type = 'passport';
  final country = TextEditingController();
  @override
  void dispose() {
    country.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => SafeArea(
    child: Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(c).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Which document?', style: Theme.of(c).textTheme.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'passport', label: Text('Passport')),
              ButtonSegment(value: 'nationalId', label: Text('National ID card')),
            ],
            selected: {type},
            onSelectionChanged: (v) => setState(() => type = v.first),
          ),
          const SizedBox(height: 8),
          if (type == 'nationalId')
            TextField(
              key: const Key('identity-country'),
              controller: country,
              maxLength: 2,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Issuing country (2 letters, e.g. DE)'),
              onChanged: (_) => setState(() {}),
            ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: type == 'nationalId' && !RegExp(r'^[A-Za-z]{2}$').hasMatch(country.text)
                ? null
                : () => Navigator.pop(c, <String, dynamic>{
                      'documentType': type,
                      if (type == 'nationalId') 'issuingCountry': country.text.toUpperCase(),
                    }),
            child: const Text('Continue'),
          ),
        ],
      ),
    ),
  );
}

class _CodeDialog extends StatefulWidget {
  const _CodeDialog();
  @override
  State<_CodeDialog> createState() => _CodeDialogState();
}

class _CodeDialogState extends State<_CodeDialog> {
  final code = TextEditingController();
  @override
  void dispose() {
    code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => AlertDialog(
    title: const Text('Code from the website'),
    content: TextField(
      key: const Key('identity-pair-code'),
      controller: code,
      keyboardType: TextInputType.number,
      maxLength: 6,
      decoration: const InputDecoration(labelText: '6-digit code'),
      onChanged: (_) => setState(() {}),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
      FilledButton(
        onPressed: RegExp(r'^\d{6}$').hasMatch(code.text) ? () => Navigator.pop(c, code.text) : null,
        child: const Text('Continue'),
      ),
    ],
  );
}

class _AppealDialog extends StatefulWidget {
  const _AppealDialog();
  @override
  State<_AppealDialog> createState() => _AppealDialogState();
}

class _AppealDialogState extends State<_AppealDialog> {
  final text = TextEditingController();
  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => AlertDialog(
    title: const Text('Appeal'),
    content: TextField(
      key: const Key('identity-appeal-statement'),
      controller: text,
      maxLines: 5,
      maxLength: 2000,
      decoration: const InputDecoration(labelText: 'Why should the decision change? (at least 10 characters)'),
      onChanged: (_) => setState(() {}),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
      FilledButton(
        onPressed: text.text.trim().length >= 10 ? () => Navigator.pop(c, text.text.trim()) : null,
        child: const Text('Send appeal'),
      ),
    ],
  );
}

/// Claims a website pairing (deep link token or 6-digit code), then opens the capture flow.
class IdentityPairPage extends StatefulWidget {
  const IdentityPairPage({super.key, this.token, this.code});
  final String? token, code;
  @override
  State<IdentityPairPage> createState() => _IdentityPairPageState();
}

class _IdentityPairPageState extends State<IdentityPairPage> {
  String? error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _claim());
  }

  Future<void> _claim() async {
    final token = widget.token, code = widget.code;
    if ((token == null || token.isEmpty) == (code == null || code.isEmpty)) {
      setState(() => error = 'This link is not valid. Start again on the TWON website.');
      return;
    }
    try {
      final session = asJson(await repository(context).request(
        'verification/pairing/claim',
        method: 'POST',
        body: token != null && token.isNotEmpty ? {'token': token} : {'code': code},
      ));
      if (mounted) context.pushReplacement('/verification/capture', extra: session);
    } on AppFailure catch (e) {
      if (mounted) setState(() => error = e.message);
    }
  }

  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(title: const Text('Continue verification')),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: error == null
            ? const CircularProgressIndicator()
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(error!, key: const Key('identity-pair-error'), textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: () => c.go('/verification'), child: const Text('Back to verification')),
                ],
              ),
      ),
    ),
  );
}

/// The capture flow for one server-issued session.
class IdentityCapturePage extends StatefulWidget {
  const IdentityCapturePage({super.key, required this.session, ImagePicker? picker}) : _picker = picker;
  final Json session;
  final ImagePicker? _picker;
  @override
  State<IdentityCapturePage> createState() => _IdentityCapturePageState();
}

class _IdentityCapturePageState extends State<IdentityCapturePage> {
  late final String sessionId = widget.session['sessionId'].toString();
  late final List<String> steps = (widget.session['steps'] as List? ?? const []).map((e) => '$e').toList();
  late final Set<String> done = {...(widget.session['received'] as List? ?? const []).map((e) => '$e')};
  final previews = <String, String>{}; // kind → local file path (never uploaded twice, never from the server)
  String? busyKind, error;
  bool submitting = false, finished = false, expired = false;
  late final ImagePicker picker = widget._picker ?? ImagePicker();

  String? get current => steps.firstWhere((k) => !done.contains(k), orElse: () => '');

  @override
  void dispose() {
    _discardPreviews();
    super.dispose();
  }

  void _discardPreviews() {
    for (final path in previews.values) {
      try {
        File(path).deleteSync();
      } catch (_) {}
    }
    previews.clear();
  }

  Future<void> _capture(String kind) async {
    final copy = identityStepCopy(kind);
    setState(() => error = null);
    // Camera only: the verification flow never offers the gallery.
    final shot = await picker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: copy.front ? CameraDevice.front : CameraDevice.rear,
      imageQuality: 92, // also turns HEIC into JPEG on iOS
    );
    if (shot == null || !mounted) return;
    final ext = shot.path.split('.').last.toLowerCase();
    if (!['jpg', 'jpeg', 'png', 'webp'].contains(ext)) {
      setState(() => error = 'This photo format is not supported. Please take the photo again.');
      return;
    }
    setState(() => previews[kind] = shot.path);
  }

  Future<void> _upload(String kind) async {
    final path = previews[kind];
    if (path == null) return;
    setState(() {
      busyKind = kind;
      error = null;
    });
    try {
      await repository(context).upload(path, endpoint: 'verification/sessions/$sessionId/evidence/$kind', fileName: '$kind.${path.split('.').last.toLowerCase()}');
      if (mounted) setState(() => done.add(kind));
    } on AppFailure catch (e) {
      if (!mounted) return;
      setState(() {
        switch (e.code) {
          case 'CAPTURE_STEP_COMPLETE':
            done.add(kind); // already received (a retry after a lost response)
          case 'CAPTURE_SESSION_EXPIRED' || 'CAPTURE_SESSION_CLOSED':
            expired = true;
            error = 'This capture has expired. Start again.';
          case 'IDENTITY_EVIDENCE_REJECTED':
            previews.remove(kind);
            error = 'This photo was refused by the security check. Please take it again.';
          default:
            error = e.message;
        }
      });
    } finally {
      if (mounted) setState(() => busyKind = null);
    }
  }

  Future<void> _submit() async {
    setState(() {
      submitting = true;
      error = null;
    });
    try {
      await repository(context).request('verification/sessions/$sessionId/submit', method: 'POST');
      _discardPreviews();
      if (!mounted) return;
      setState(() => finished = true);
      notice(context, 'Submitted. A reviewer will check your verification.');
      context.go('/verification');
    } on AppFailure catch (e) {
      if (mounted) {
        setState(() {
          expired = e.code == 'CAPTURE_SESSION_EXPIRED' || e.code == 'CAPTURE_SESSION_CLOSED';
          error = e.message;
        });
      }
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  Future<void> _cancel() async {
    try {
      await repository(context).request('verification/sessions/$sessionId', method: 'DELETE');
    } on AppFailure catch (_) {
      // Already closed or expired: nothing to cancel.
    }
    _discardPreviews();
    if (mounted) context.go('/verification');
  }

  @override
  Widget build(BuildContext c) {
    final kind = current ?? '';
    final allDone = steps.isNotEmpty && steps.every(done.contains);
    return Scaffold(
      appBar: AppBar(
        title: Text('Step ${(done.length + (allDone ? 0 : 1)).clamp(1, steps.length)} of ${steps.length}'),
        actions: [TextButton(onPressed: submitting ? null : _cancel, child: const Text('Cancel'))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (error != null)
            Card(
              color: Theme.of(c).colorScheme.errorContainer,
              child: Padding(padding: const EdgeInsets.all(12), child: Text(error!, key: const Key('identity-capture-error'))),
            ),
          if (expired)
            FilledButton(onPressed: () => c.go('/verification'), child: const Text('Start again'))
          else if (!allDone && kind.isNotEmpty) ...[
            Text(identityStepCopy(kind).title, style: Theme.of(c).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(identityStepCopy(kind).hint),
            const SizedBox(height: 16),
            if (previews[kind] != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                // Local preview only: the file on this phone, never an image from the server.
                child: Image.file(File(previews[kind]!), key: Key('identity-preview-$kind'), height: 320, fit: BoxFit.contain),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(onPressed: busyKind != null ? null : () => _capture(kind), child: const Text('Retake')),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: busyKind != null ? null : () => _upload(kind),
                      child: busyKind == kind ? const Text('Sending…') : const Text('Use this photo'),
                    ),
                  ),
                ],
              ),
            ] else
              FilledButton.icon(
                onPressed: () => _capture(kind),
                icon: const Icon(Icons.photo_camera_outlined),
                label: Text(identityStepCopy(kind).front ? 'Open front camera' : 'Open camera'),
              ),
          ] else if (allDone && !finished) ...[
            Text('All photos are ready', style: Theme.of(c).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text('Submit them for review. You can\'t change them after submitting.'),
            const SizedBox(height: 16),
            FilledButton(onPressed: submitting ? null : _submit, child: Text(submitting ? 'Submitting…' : 'Submit for review')),
          ],
          const SizedBox(height: 24),
          for (final k in steps)
            ListTile(
              dense: true,
              leading: Icon(done.contains(k) ? Icons.check_circle : Icons.radio_button_unchecked),
              title: Text(identityStepCopy(k).title),
            ),
        ],
      ),
    );
  }
}
