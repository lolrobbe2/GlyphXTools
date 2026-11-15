import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:glyphxtools/convert/archive.dart';
import 'package:glyphxtools/files/meg/mega_file_archive.dart';
import 'package:material_ui/material_ui.dart';

class ConvertersPage extends StatefulWidget {
  const ConvertersPage({super.key});

  @override
  State<ConvertersPage> createState() => _ConvertersPageState();
}

class _ConvertersPageState extends State<ConvertersPage> {
  String? _selectedFileName;
  String? _outputFileName;

  Uint8List? _zipBytes;

  bool _isConverting = false;
  bool _isSaving = false;

  String? _errorMessage;
  double? _conversionProgress;

  String _progressStatus = 'Reading MEG file...';

  int _completedFiles = 0;
  int _totalFiles = 0;
  Future<void> _selectMegFile() async {
    try {
      final List<PlatformFile> files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['meg'],
      );

      if (files.isEmpty) {
        return;
      }

      setState(() {
        _selectedFileName = files.single.name;
        _outputFileName = files.single.name.replaceFirst(
          RegExp(r'\.meg$', caseSensitive: false),
          '.zip',
        );
        _zipBytes = null;
        _errorMessage = null;
      });

      await _convertFile(files.single);
    } catch (error) {
      setState(() {
        _errorMessage = 'Could not select file: $error';
      });
    }
  }

  Future<void> _convertFile(PlatformFile file) async {
    setState(() {
      _isConverting = true;
      _errorMessage = null;
      _zipBytes = null;

      _conversionProgress = null;
      _progressStatus = 'Reading MEG file index...';

      _completedFiles = 0;
      _totalFiles = 0;
    });
    try {
      final MegaFileArchive archive = await MegaFileArchive.fromStream(
        file.readAsByteStream(),
      );

      final Uint8List result = await MegToZipConverter.convert(
        archive,
        onProgress:
            ({
              required String status,
              required double progress,
              required int completedFiles,
              required int totalFiles,
            }) {
              if (!mounted) {
                return;
              }

              setState(() {
                _progressStatus = status;
                _conversionProgress = progress;
                _completedFiles = completedFiles;
                _totalFiles = totalFiles;
              });
            },
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _zipBytes = result;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = 'Conversion failed: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isConverting = false;
        });
      }
    }
  }

  Future<void> _saveZipFile() async {
    if (_zipBytes == null || _outputFileName == null) {
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final String fileName = _outputFileName!.replaceFirst(
        RegExp(r'\.zip$', caseSensitive: false),
        '',
      );

      await FileSaver.instance.saveFile(
        name: fileName,
        bytes: _zipBytes!,
        fileExtension: 'zip',
        mimeType: MimeType.zip,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = 'Could not save ZIP file: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Converters',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Convert files between different formats.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 32),

              _buildMegToZipCard(),

              if (_errorMessage != null) ...[
                const SizedBox(height: 20),
                Text(
                  _errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMegToZipCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.folder_zip_outlined, size: 32),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'MEG to ZIP',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Extract a MEG archive into a standard ZIP archive.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),

            OutlinedButton.icon(
              onPressed: _isConverting ? null : _selectMegFile,
              icon: const Icon(Icons.file_open),
              label: const Text('Select MEG file'),
            ),

            if (_selectedFileName != null) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  const Icon(Icons.insert_drive_file_outlined),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _selectedFileName!,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],

            if (_isConverting) ...[
              const SizedBox(height: 24),

              Row(
                children: [
                  Expanded(
                    child: Text(
                      _progressStatus,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (_conversionProgress != null)
                    Text(
                      '${(_conversionProgress! * 100).round()}%',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                ],
              ),

              const SizedBox(height: 12),

              LinearProgressIndicator(
                value: _conversionProgress,
                minHeight: 8,
                borderRadius: BorderRadius.circular(8),
              ),

              if (_totalFiles > 0) ...[
                const SizedBox(height: 8),
                Text(
                  '$_completedFiles / $_totalFiles files',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],

            if (_zipBytes != null) ...[
              const SizedBox(height: 24),
              Row(
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('Conversion completed successfully.'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Output: $_outputFileName',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _isSaving ? null : _saveZipFile,
                icon: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download),
                label: Text(_isSaving ? 'Saving...' : 'Download ZIP'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
