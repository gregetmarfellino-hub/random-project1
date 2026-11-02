import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

class QrScannerPage extends StatefulWidget {
  const QrScannerPage({super.key});

  @override
  State<QrScannerPage> createState() =>
      _QrScannerPageState();
}

class _QrScannerPageState
    extends State<QrScannerPage> {
  late final MobileScannerController
      _controller;

  bool _didReturnResult = false;

  @override
  void initState() {
    super.initState();

    _controller =
        MobileScannerController(
      facing:
          CameraFacing.back,
      detectionSpeed:
          DetectionSpeed.noDuplicates,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleDetection(
    BarcodeCapture capture,
  ) {
    if (_didReturnResult) return;

    for (final barcode
        in capture.barcodes) {
      final value =
          barcode.rawValue?.trim();

      if (value != null &&
          value.isNotEmpty) {
        _didReturnResult = true;

        Navigator.of(context)
            .pop(value);

        return;
      }
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      backgroundColor:
          Colors.black,

      appBar: AppBar(
        title: const Text(
          "Scan PC",
        ),

        backgroundColor:
            Colors.black,

        foregroundColor:
            Colors.white,

        actions: [
          IconButton(
            tooltip: "Flash",

            icon: const Icon(
              Icons.flash_on,
            ),

            onPressed: () {
              _controller
                  .toggleTorch();
            },
          ),

          IconButton(
            tooltip:
                "Switch camera",

            icon: const Icon(
              Icons.flip_camera_android,
            ),

            onPressed: () {
              _controller
                  .switchCamera();
            },
          ),
        ],
      ),

      body: Stack(
        fit: StackFit.expand,

        children: [
          MobileScanner(
            controller:
                _controller,

            onDetect:
                _handleDetection,

           errorBuilder: (context, error) {
              return Container(
                color:
                    Colors.black,

                alignment:
                    Alignment.center,

                padding:
                    const EdgeInsets
                        .all(24),

                child: Column(
                  mainAxisSize:
                      MainAxisSize.min,

                  children: [
                    const Icon(
                      Icons
                          .camera_alt_outlined,
                      color:
                          Colors.redAccent,
                      size: 64,
                    ),

                    const SizedBox(
                      height: 16,
                    ),

                    const Text(
                      "Camera unavailable",
                      textAlign:
                          TextAlign.center,
                      style:
                          TextStyle(
                        color:
                            Colors.white,
                        fontSize: 20,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),

                    const SizedBox(
                      height: 10,
                    ),

                    const Text(
                      'Check camera permission in Settings, then try again.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),

                    const SizedBox(
                      height: 20,
                    ),

                    FilledButton.icon(
                      onPressed: () {
                        openAppSettings();
                      },

                      icon:
                          const Icon(
                        Icons.settings,
                      ),

                      label:
                          const Text(
                        "Open settings",
                      ),
                    ),

                    const SizedBox(
                      height: 8,
                    ),

                    TextButton(
                      onPressed: () {
                        Navigator.of(
                          context,
                        ).pop();
                      },

                      child:
                          const Text(
                        "Back",
                      ),
                    ),
                  ],
                ),
              );
            },

            overlayBuilder:
                (context,
                    constraints) {
              final size =
                  constraints
                      .biggest;

              final boxSize =
                  size.shortestSide *
                      0.70;

              return Center(
                child: SizedBox(
                  width: boxSize,
                  height: boxSize,

                  child:
                      DecoratedBox(
                    decoration:
                        BoxDecoration(
                      border:
                          Border.all(
                        color:
                            const Color(
                          0xFF89B4FA,
                        ),
                        width: 3,
                      ),

                      borderRadius:
                          BorderRadius
                              .circular(
                        20,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),

          Positioned(
            left: 24,
            right: 24,
            bottom: 30,

            child:
                IgnorePointer(
              child:
                  Container(
                padding:
                    const EdgeInsets
                        .symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),

                decoration:
                    BoxDecoration(
                  color: Colors.black
                      .withValues(
                    alpha: 0.70,
                  ),

                  borderRadius:
                      BorderRadius
                          .circular(
                    14,
                  ),
                ),

                child:
                    const Text(
                  "Point the camera at the PyClean QR code",

                  textAlign:
                      TextAlign.center,

                  style:
                      TextStyle(
                    color:
                        Colors.white,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
