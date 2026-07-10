import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:async';
import '../config/credentials.dart';
import '../config/token_utils.dart';
import '../services/dive_sdk_service.dart';
import '../models/dive_result.dart';

/// DIVE Online SDK Tab Screen
class DiveOnlineSdkScreen extends StatefulWidget {
  const DiveOnlineSdkScreen({super.key});

  @override
  State<DiveOnlineSdkScreen> createState() => _DiveOnlineSdkScreenState();
}

class _DiveOnlineSdkScreenState extends State<DiveOnlineSdkScreen> {
  Map<String, dynamic>? _resultData;
  bool _isPublicKey = false;
  StreamSubscription<double>? _progressSubscription;
  bool _uploadDialogShown = false;
  bool _isProcessing = false;

  @override
  void dispose() {
    _progressSubscription?.cancel();
    super.dispose();
  }

  Future<void> _startDiveOnlineSdk() async {
    if (_isProcessing) return;

    setState(() {
      _isProcessing = true;
      _resultData = null;
      _uploadDialogShown = false;
    });

    try {
      // Subscribe to upload progress
      _progressSubscription = DiveSDKService.uploadProgressStream.listen(
        (progress) {
          if (!_uploadDialogShown && mounted) {
            _uploadDialogShown = true;
            // Show uploading dialog when first progress event arrives
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (context) => StreamBuilder<double>(
                stream: DiveSDKService.uploadProgressStream,
                initialData: progress,
                builder: (context, snapshot) {
                  final currentProgress = snapshot.data ?? 0.0;
                  return AlertDialog(
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Uploading data...',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 20),
                        LinearProgressIndicator(
                          value: currentProgress > 0 ? currentProgress : null,
                          backgroundColor: Colors.grey[300],
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            Color(0xFF2B65EC),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          currentProgress > 0
                              ? '${(currentProgress * 100).toInt()}%'
                              : 'Preparing...',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            );
          }
        },
        onError: (error) {
          debugPrint('Upload progress error: $error');
        },
      );

      // Launch DIVE Online SDK (iOS will create applicant using DIVEOnlineSDK.getApplicantID)
      final result = await DiveSDKService.launchDiveOnline(
        token: DiveCredentials.diveOnlineToken,
        integrationId: DiveCredentials.diveOnlineIntegrationId,
        baseUrl: DiveCredentials.diveOnlineBaseUrl,
        firstName: DiveCredentials.applicantFirstName,
        lastName: DiveCredentials.applicantLastName,
        phone: DiveCredentials.applicantPhone,
      );

      // Cancel progress subscription
      await _progressSubscription?.cancel();
      _progressSubscription = null;

      // Dismiss uploading dialog if it was shown
      if (_uploadDialogShown && mounted) {
        Navigator.of(context).pop();
        _uploadDialogShown = false;
      }

      if (!mounted) return;

      // Handle result
      switch (result) {
        case DiveSuccess(:final requestKey, :final fullResult):
          // Determine if token is public or secret key
          _isPublicKey = TokenUtils.isPublicKey(
            DiveCredentials.diveOnlineToken,
          );

          setState(() {
            _resultData =
                fullResult ??
                {
                  'success': true,
                  'requestKey': requestKey,
                };
            _isProcessing = false;
          });
          break;

        case DiveError(:final code, :final message):
          setState(() {
            _isProcessing = false;
          });

          // Show error dialog
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Error'),
              content: Text('$code\n$message'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
          break;

        case DiveCancelled():
          setState(() {
            _resultData = null;
            _isProcessing = false;
          });

          // Show cancellation dialog
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Cancelled'),
              content: const Text('Scanning was cancelled by user'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
          break;
      }
    } catch (e) {
      // Cancel progress subscription
      await _progressSubscription?.cancel();
      _progressSubscription = null;

      // Dismiss uploading dialog if it was shown
      if (_uploadDialogShown && mounted) {
        Navigator.of(context).pop();
        _uploadDialogShown = false;
      }

      setState(() {
        _isProcessing = false;
      });

      if (!mounted) return;

      // Show error
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Error'),
          content: Text('Failed to start DIVE Online SDK: $e'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Center(
          child: Column(
            children: [
              const SizedBox(height: 60),
              // Title
              const Text(
                'DIVE Online SDK',
                style: TextStyle(fontSize: 25, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 60),

              // Start Button
              SizedBox(
                width: 200,
                height: 44,
                child: ElevatedButton(
                  onPressed: _isProcessing ? null : _startDiveOnlineSdk,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2B65EC),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(
                      0xFF2B65EC,
                    ).withValues(alpha: 0.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  child: _isProcessing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Start DIVE Online',
                          style: TextStyle(fontSize: 17),
                        ),
                ),
              ),

              // Results section
              if (_resultData != null) ...[
                const SizedBox(height: 40),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: _isPublicKey
                      ? _buildPublicKeyResults()
                      : _buildDetailedResults(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Build results for public key (pk_) tokens
  Widget _buildPublicKeyResults() {
    final requestId = _resultData?['requestId'] as String?;

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.info_outline, color: Color(0xFF2B65EC)),
                SizedBox(width: 8),
                Text(
                  'Verification Complete',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Document scanned successfully. Use the Request ID below to retrieve full verification results via API.',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Request ID:',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    requestId ?? 'N/A',
                    style: const TextStyle(
                      fontSize: 14,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'API Documentation:',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const SelectableText(
              'https://docs.idscan.net/dive/dive-api/swagger.html',
              style: TextStyle(
                fontSize: 12,
                color: Color(0xFF2B65EC),
                decoration: TextDecoration.underline,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build detailed results for secret key (sk_) tokens
  Widget _buildDetailedResults() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Verification Results',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _buildDataTable(_resultData!, 0),
          ],
        ),
      ),
    );
  }

  /// Build recursive data table
  Widget _buildDataTable(Map<String, dynamic> data, int depth) {
    final List<Widget> rows = [];

    data.forEach((key, value) {
      // Skip null or empty values
      if (value == null || (value is String && value.isEmpty)) {
        return;
      }

      rows.add(_buildRow(key, value, depth));
    });

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows);
  }

  /// Build a single row
  Widget _buildRow(String key, dynamic value, int depth) {
    // Cap indentation at depth 2 to prevent horizontal overflow
    final cappedDepth = depth > 2 ? 2 : depth;
    final indent = cappedDepth * 16.0;

    // Check if value is a base64 image
    if (value is String && _isBase64Image(value)) {
      return Padding(
        padding: EdgeInsets.only(left: indent, bottom: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _formatKey(key),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 8),
            _buildImage(value),
          ],
        ),
      );
    }

    // Handle nested objects
    if (value is Map<String, dynamic>) {
      return Padding(
        padding: EdgeInsets.only(left: indent, bottom: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _formatKey(key),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: Color(0xFF2B65EC),
              ),
            ),
            const SizedBox(height: 8),
            _buildDataTable(value, depth + 1),
          ],
        ),
      );
    }

    // Handle lists
    if (value is List) {
      return Padding(
        padding: EdgeInsets.only(left: indent, bottom: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _formatKey(key),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 8),
            ...value.asMap().entries.map((entry) {
              return _buildRow('[${entry.key}]', entry.value, depth + 1);
            }),
          ],
        ),
      );
    }

    // Handle primitive values
    // Use Column layout for nested items to avoid horizontal overflow
    if (depth > 0) {
      return Padding(
        padding: EdgeInsets.only(left: indent, bottom: 8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _formatKey(key),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 4),
            SelectableText(
              _formatValue(value),
              style: const TextStyle(fontSize: 14),
            ),
          ],
        ),
      );
    }

    // Top-level items can use Row layout
    return Padding(
      padding: EdgeInsets.only(left: indent, bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              _formatKey(key),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: SelectableText(
              _formatValue(value),
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  /// Build image widget from base64 string
  Widget _buildImage(String base64String) {
    try {
      // Remove data:image prefix if present
      String cleanBase64 = base64String;
      if (base64String.contains(',')) {
        cleanBase64 = base64String.split(',')[1];
      }

      final bytes = base64Decode(cleanBase64);
      return Container(
        constraints: const BoxConstraints(maxWidth: 300, maxHeight: 300),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[300]!),
          borderRadius: BorderRadius.circular(8),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(bytes, fit: BoxFit.contain),
        ),
      );
    } catch (e) {
      return Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.red[50],
          border: Border.all(color: Colors.red[300]!),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          'Failed to load image: $e',
          style: TextStyle(color: Colors.red[900], fontSize: 12),
        ),
      );
    }
  }

  /// Check if string is a base64 encoded image
  bool _isBase64Image(String value) {
    if (value.length < 100) return false;

    if (value.startsWith('data:image/') ||
        value.startsWith('/9j/') ||
        value.startsWith('iVBORw0KGgo')) {
      return true;
    }

    return false;
  }

  /// Format key for display
  String _formatKey(String key) {
    final words = key.replaceAllMapped(
      RegExp(r'([A-Z])'),
      (match) => ' ${match.group(1)}',
    );
    return words[0].toUpperCase() + words.substring(1);
  }

  /// Format value for display
  String _formatValue(dynamic value) {
    if (value is bool) {
      return value ? 'Yes' : 'No';
    }
    if (value is num) {
      return value.toString();
    }
    return value.toString();
  }
}
