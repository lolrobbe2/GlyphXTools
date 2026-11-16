import 'package:flutter/widgets.dart';

import 'package:glyphxtools/files/meg/mega_file.dart';
import 'package:glyphxtools/widgets/mega_dds_viewer.dart';
import 'package:glyphxtools/widgets/mega_h_viewer.dart';
import 'package:glyphxtools/widgets/mega_rc_viewer.dart';
import 'package:glyphxtools/widgets/mega_xml_viewer.dart';

class MegaFileViewer extends StatelessWidget {
  const MegaFileViewer({
    super.key,
    required this.file,
    this.backgroundColor = const Color(0xFF181818),
    this.showInfo = true,
  });

  final MegaFile file;
  final Color backgroundColor;
  final bool showInfo;

  String get _extension {
    final String normalizedPath = file.path.replaceAll('\\', '/');
    final String fileName = normalizedPath.split('/').last;

    final int dotIndex = fileName.lastIndexOf('.');

    if (dotIndex <= 0) {
      return '';
    }

    return fileName.substring(dotIndex).toLowerCase();
  }

  @override
  Widget build(BuildContext context) {
    switch (_extension) {
      case '.dds':
        return MegaDdsViewer(
          file: file,
          backgroundColor: backgroundColor,
          showInfo: showInfo,
        );
      case '.xml':
        return MegaXmlViewer(
          file: file,
          backgroundColor: backgroundColor,
          showInfo: showInfo,
        );
      case '.rc':
        return MegaRcViewer(
          file: file,
          backgroundColor: backgroundColor,
          showInfo: showInfo,
        );
      case '.h':
        return MegaHViewer(
          file: file,
          showInfo: true,
        );
      default:
        return _buildUnsupportedViewer();
    }
  }

  Widget _buildUnsupportedViewer() {
    final String fileName = file.path.replaceAll('\\', '/').split('/').last;

    return ColoredBox(
      color: backgroundColor,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                IconData(0xe24d, fontFamily: 'MaterialIcons'),
                size: 48,
                color: Color(0xFFAAAAAA),
              ),
              const SizedBox(height: 16),
              const Text(
                'Preview not available',
                style: TextStyle(
                  color: Color(0xFFFFFFFF),
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                fileName,
                style: const TextStyle(color: Color(0xFFAAAAAA)),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                'Unsupported file type: ${_extension.isEmpty ? 'Unknown' : _extension}',
                style: const TextStyle(color: Color(0xFF888888)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
