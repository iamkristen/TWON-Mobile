import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import '../core/models.dart';
import '../core/collection_cubit.dart';
import 'widgets.dart';

enum FieldKind {
  text,
  multiline,
  email,
  password,
  integer,
  decimal,
  date,
  time,
  toggle,
  select,
  image,
  images,
  files,
}

class FieldSpec {
  const FieldSpec(
    this.key,
    this.label, {
    this.kind = FieldKind.text,
    this.required = true,
    this.options = const [],
    this.initial,
    this.maxLength,
    this.hint,
  });
  final String key, label;
  final FieldKind kind;
  final bool required;
  final List<String> options;
  final dynamic initial;
  final int? maxLength;
  final String? hint;
}

class FeatureForm extends StatefulWidget {
  const FeatureForm({
    super.key,
    required this.title,
    required this.fields,
    required this.submit,
    this.onSuccess,
    this.button = 'Save',
    this.description,
    this.embedded = false,
  });
  final bool embedded;
  final String title, button;
  final String? description;
  final List<FieldSpec> fields;
  final Future<dynamic> Function(Json) submit;
  final void Function(dynamic)? onSuccess;
  @override
  State<FeatureForm> createState() => _FeatureFormState();
}

class _FeatureFormState extends State<FeatureForm> {
  final form = GlobalKey<FormState>();
  final values = <String, dynamic>{};
  final controllers = <String, TextEditingController>{};
  final mutation = MutationCubit();
  bool uploadBusy = false;
  String? uploadError;
  double? progress;
  @override
  void initState() {
    super.initState();
    for (final f in widget.fields) {
      values[f.key] =
          f.initial ??
          (f.kind == FieldKind.toggle
              ? false
              : f.kind == FieldKind.select && f.options.isNotEmpty
              ? f.options.first
              : f.kind == FieldKind.images || f.kind == FieldKind.files
              ? <String>[]
              : '');
      controllers[f.key] = TextEditingController(
        text: values[f.key] is String || values[f.key] is num
            ? '${values[f.key]}'
            : '',
      );
    }
  }

  @override
  void dispose() {
    for (final c in controllers.values) {
      c.dispose();
    }
    mutation.close();
    super.dispose();
  }

  Future<void> pick(FieldSpec f) async {
    setState(() => uploadError = null);
    try {
      List<String> paths = [];
      if (f.kind == FieldKind.files) {
        final picked = await FilePicker.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
        );
        paths = picked.map((e) => e.path).whereType<String>().toList();
        if ((await Future.wait(
          paths.map((path) => File(path).length()),
        )).any((size) => size > 10 * 1024 * 1024)) {
          throw const AppFailure('Each attachment must be under 10 MB.');
        }
      } else {
        final source = await showModalBottomSheet<ImageSource>(
          context: context,
          builder: (c) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: const Text('Photo library'),
                  onTap: () => Navigator.pop(c, ImageSource.gallery),
                ),
                ListTile(
                  leading: const Icon(Icons.camera_alt_outlined),
                  title: const Text('Take a photo'),
                  onTap: () => Navigator.pop(c, ImageSource.camera),
                ),
              ],
            ),
          ),
        );
        if (source == null) return;
        final picker = ImagePicker();
        if (f.kind == FieldKind.images && source == ImageSource.gallery) {
          paths = (await picker.pickMultiImage(
            maxWidth: 1800,
            imageQuality: 85,
          )).map((e) => e.path).toList();
        } else {
          final file = await picker.pickImage(
            source: source,
            maxWidth: 1800,
            imageQuality: 85,
          );
          if (file != null) paths = [file.path];
        }
      }
      if (paths.isEmpty || !mounted) return;
      final old = values[f.key] is List
          ? List<String>.from(values[f.key])
          : <String>[];
      if (old.length + paths.length > 5) {
        throw const AppFailure('Choose up to five attachments.');
      }
      setState(() => uploadBusy = true);
      for (final path in paths) {
        if (!mounted) return;
        final api = repository(context);
        final result = await api.upload(
          path,
          progress: (sent, total) {
            if (mounted) {
              setState(() => progress = total > 0 ? sent / total : null);
            }
          },
        );
        if (!mounted) return;
        setState(
          () => values[f.key] = f.kind == FieldKind.image
              ? result['url']
              : ([
                  ...List<String>.from(values[f.key] as List),
                  result['url'] as String,
                ]),
        );
      }
    } catch (error) {
      if (mounted) setState(() => uploadError = error.toString());
    } finally {
      if (mounted) {
        setState(() {
          uploadBusy = false;
          progress = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => BlocProvider.value(
    value: mutation,
    child: BlocConsumer<MutationCubit, MutationState>(
      listener: (c, s) {
        if (s.success) {
          FocusScope.of(c).unfocus();
          widget.onSuccess?.call(s.result);
        }
      },
      builder: (c, s) => _formContainer(
        child: Form(
          key: form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.embedded)
                Padding(
                  padding: const EdgeInsets.only(bottom: 28),
                  child: Column(
                    children: [
                      Text(
                        widget.title,
                        textAlign: TextAlign.center,
                        style: Theme.of(c).textTheme.headlineSmall,
                      ),
                      if (widget.description != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          widget.description!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Theme.of(c).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                )
              else
                PageHeading(widget.title, widget.description ?? ''),
              ...widget.fields.map(
                (f) => Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: buildField(f, s.busy),
                ),
              ),
              if (uploadBusy) LinearProgressIndicator(value: progress),
              if (uploadError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    uploadError!,
                    style: TextStyle(color: Theme.of(c).colorScheme.error),
                  ),
                ),
              if (s.error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    s.error!,
                    style: TextStyle(color: Theme.of(c).colorScheme.error),
                  ),
                ),
              FilledButton(
                onPressed: s.busy || uploadBusy
                    ? null
                    : () {
                        if (!form.currentState!.validate()) return;
                        for (final f in widget.fields) {
                          if (![
                            FieldKind.toggle,
                            FieldKind.select,
                            FieldKind.image,
                            FieldKind.images,
                            FieldKind.files,
                          ].contains(f.kind)) {
                            final text = controllers[f.key]!.text;
                            if (!f.required &&
                                text.trim().isEmpty &&
                                [
                                  FieldKind.integer,
                                  FieldKind.decimal,
                                ].contains(f.kind)) {
                              values.remove(f.key);
                              continue;
                            }
                            values[f.key] = f.kind == FieldKind.integer
                                ? int.parse(text)
                                : f.kind == FieldKind.decimal
                                ? double.parse(text)
                                : f.kind == FieldKind.password
                                ? text
                                : text.trim();
                          }
                        }
                        mutation.run(() => widget.submit({...values}));
                      },
                child: s.busy
                    ? const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(widget.button),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  Widget _formContainer({required Widget child}) => widget.embedded
      ? child
      : SingleChildScrollView(padding: const EdgeInsets.all(20), child: child);

  Widget buildField(FieldSpec f, bool busy) {
    final label = '${f.label}${f.required ? '' : ' (optional)'}';
    if (f.kind == FieldKind.toggle) {
      return SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: Text(f.label),
        value: values[f.key] == true,
        onChanged: busy ? null : (v) => setState(() => values[f.key] = v),
      );
    }
    if (f.kind == FieldKind.select) {
      return DropdownButtonFormField<String>(
        initialValue: values[f.key] as String,
        decoration: InputDecoration(labelText: label),
        isExpanded: true,
        items: f.options
            .map((v) => DropdownMenuItem(value: v, child: Text(v)))
            .toList(),
        onChanged: busy ? null : (v) => values[f.key] = v,
      );
    }
    if ([FieldKind.image, FieldKind.images, FieldKind.files].contains(f.kind)) {
      final urls = values[f.key] is List
          ? List<String>.from(values[f.key])
          : values[f.key].toString().isEmpty
          ? <String>[]
          : [values[f.key].toString()];
      return FormField<List<String>>(
        validator: (_) =>
            f.required && urls.isEmpty ? 'Add ${f.label.toLowerCase()}.' : null,
        builder: (state) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(label, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            ...urls.asMap().entries.map(
              (e) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Attachment ${e.key + 1}'),
                leading: f.kind != FieldKind.files
                    ? BrandImage(e.value, height: 48, width: 48)
                    : const Icon(Icons.attach_file),
                trailing: IconButton(
                  tooltip: 'Remove attachment',
                  onPressed: uploadBusy || busy
                      ? null
                      : () => setState(
                          () => values[f.key] = f.kind == FieldKind.image
                              ? ''
                              : urls.where((u) => u != e.value).toList(),
                        ),
                  icon: const Icon(Icons.close),
                ),
              ),
            ),
            OutlinedButton.icon(
              onPressed: uploadBusy || busy ? null : () => pick(f),
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: const Text('Add attachment'),
            ),
            if (state.hasError)
              Text(
                state.errorText!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      );
    }
    final date = f.kind == FieldKind.date, time = f.kind == FieldKind.time;
    return TextFormField(
      controller: controllers[f.key],
      onTapOutside: widget.embedded
          ? (_) => FocusManager.instance.primaryFocus?.unfocus()
          : null,
      enabled: !busy,
      readOnly: date || time,
      obscureText: f.kind == FieldKind.password,
      maxLength: f.maxLength,
      minLines: f.kind == FieldKind.multiline ? 4 : 1,
      maxLines: f.kind == FieldKind.multiline ? 8 : 1,
      keyboardType: f.kind == FieldKind.email
          ? TextInputType.emailAddress
          : [FieldKind.integer, FieldKind.decimal].contains(f.kind)
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      autofillHints: f.kind == FieldKind.password
          ? [AutofillHints.password]
          : f.kind == FieldKind.email
          ? [AutofillHints.email]
          : null,
      decoration: InputDecoration(
        labelText: label,
        helperText: f.hint,
        suffixIcon: date
            ? const Icon(Icons.calendar_today)
            : time
            ? const Icon(Icons.schedule)
            : null,
      ),
      validator: (v) {
        if (f.required && (v ?? '').trim().isEmpty) {
          return 'Enter ${f.label.toLowerCase()}.';
        }
        final value = (v ?? '').trim();
        if (!f.required && value.isEmpty) return null;
        if (f.kind == FieldKind.email &&
            !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value)) {
          return 'Enter a valid email.';
        }
        if (f.kind == FieldKind.integer && int.tryParse(v ?? '') == null) {
          return 'Enter a whole number.';
        }
        if (f.kind == FieldKind.decimal &&
            (double.tryParse(value)?.isFinite != true)) {
          return 'Enter a number.';
        }
        return null;
      },
      onTap: date
          ? () async {
              final d = await showDatePicker(
                context: context,
                initialDate:
                    DateTime.tryParse(controllers[f.key]!.text) ??
                    DateTime.now(),
                firstDate: DateTime(1900),
                lastDate: DateTime(2100),
              );
              if (mounted && d != null) {
                controllers[f.key]!.text = d.toIso8601String().split('T').first;
              }
            }
          : time
          ? () async {
              final t = await showTimePicker(
                context: context,
                initialTime: TimeOfDay.now(),
              );
              if (mounted && t != null) {
                controllers[f.key]!.text =
                    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
              }
            }
          : null,
    );
  }
}
