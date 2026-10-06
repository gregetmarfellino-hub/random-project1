import 'dart:math';

import 'package:flutter/material.dart';

class ArHologramWidget
    extends StatefulWidget {
  final bool isDir;

  const ArHologramWidget({
    super.key,
    required this.isDir,
  });

  @override
  State<ArHologramWidget>
      createState() =>
          _ArHologramWidgetState();
}

class _ArHologramWidgetState
    extends State<ArHologramWidget>
    with
        SingleTickerProviderStateMixin {
  late AnimationController
      _controller;

  @override
  void initState() {
    super.initState();

    _controller =
        AnimationController(
      vsync: this,
      duration:
          const Duration(
        seconds: 5,
      ),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _buildCubeFace(
    Color color,
    Matrix4 transform,
  ) {
    const double faceSize =
        85.0;

    return Transform(
      transform: transform,
      alignment:
          Alignment.center,

      child: Container(
        width: faceSize,
        height: faceSize,

        decoration:
            BoxDecoration(
          color:
              color.withValues(
            alpha: 0.85,
          ),

          border:
              Border.all(
            color:
                const Color(
              0xFFF9E2AF,
            ),
            width: 2.0,
          ),

          boxShadow: [
            BoxShadow(
              color:
                  const Color(
                0xFFF9E2AF,
              ).withValues(
                alpha: 0.4,
              ),

              blurRadius: 15,
              spreadRadius: 2,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilePaneFace(
    Color color,
    Matrix4 transform, {
    bool isFront = false,
  }) {
    const double paneWidth =
        85.0;

    const double paneHeight =
        115.0;

    return Transform(
      transform: transform,
      alignment:
          Alignment.center,

      child: Container(
        width: paneWidth,
        height: paneHeight,

        padding:
            const EdgeInsets.all(
          12,
        ),

        decoration:
            BoxDecoration(
          color:
              color.withValues(
            alpha: 0.35,
          ),

          borderRadius:
              BorderRadius.circular(
            6,
          ),

          border:
              Border.all(
            color:
                const Color(
              0xFF89B4FA,
            ),
            width: 1.8,
          ),

          boxShadow: [
            BoxShadow(
              color:
                  const Color(
                0xFF89B4FA,
              ).withValues(
                alpha: 0.3,
              ),

              blurRadius: 12,
              spreadRadius: 1,
            ),
          ],
        ),

        child: isFront
            ? Column(
                mainAxisAlignment:
                    MainAxisAlignment
                        .center,

                children: [
                  const Icon(
                    Icons.description,
                    color:
                        Color(
                      0xFF89B4FA,
                    ),
                    size: 36,
                  ),

                  const SizedBox(
                    height: 8,
                  ),

                  Container(
                    height: 3,
                    width: 40,
                    color:
                        Colors.white38,
                  ),

                  const SizedBox(
                    height: 4,
                  ),

                  Container(
                    height: 3,
                    width: 30,
                    color:
                        Colors.white24,
                  ),

                  const SizedBox(
                    height: 4,
                  ),

                  Container(
                    height: 3,
                    width: 35,
                    color:
                        Colors.white24,
                  ),
                ],
              )
            : null,
      ),
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return AnimatedBuilder(
      animation:
          _controller,

      builder:
          (context, child) {
        double angle =
            _controller.value *
                2 *
                pi;

        return SizedBox(
          height: 180,
          width: 180,

          child: Center(
            child: widget.isDir
                ? Transform(
                    transform:
                        Matrix4.identity()
                          ..setEntry(
                            3,
                            2,
                            0.0018,
                          )
                          ..rotateX(
                            0.4,
                          )
                          ..rotateY(
                            angle,
                          )
                          ..rotateZ(
                            0.1,
                          ),

                    alignment:
                        Alignment.center,

                    child: Stack(
                      children: [
                        _buildCubeFace(
                          Colors.amber
                              .shade800,

                          Matrix4
                              .identity()
                            ..translate(
                              0.0,
                              0.0,
                              -42.5,
                            ),
                        ),

                        _buildCubeFace(
                          Colors.amber
                              .shade700,

                          Matrix4
                              .identity()
                            ..rotateY(
                              pi / 2,
                            )
                            ..translate(
                              0.0,
                              0.0,
                              -42.5,
                            ),
                        ),

                        _buildCubeFace(
                          Colors.amber
                              .shade700,

                          Matrix4
                              .identity()
                            ..rotateY(
                              -pi / 2,
                            )
                            ..translate(
                              0.0,
                              0.0,
                              -42.5,
                            ),
                        ),

                        _buildCubeFace(
                          Colors.amber
                              .shade400,

                          Matrix4
                              .identity()
                            ..rotateX(
                              pi / 2,
                            )
                            ..translate(
                              0.0,
                              0.0,
                              -42.5,
                            ),
                        ),

                        _buildCubeFace(
                          Colors.amber
                              .shade900,

                          Matrix4
                              .identity()
                            ..rotateX(
                              -pi / 2,
                            )
                            ..translate(
                              0.0,
                              0.0,
                              -42.5,
                            ),
                        ),

                        _buildCubeFace(
                          Colors.amber
                              .shade300,

                          Matrix4
                              .identity()
                            ..translate(
                              0.0,
                              0.0,
                              42.5,
                            ),
                        ),
                      ],
                    ),
                  )
                : Transform(
                    transform:
                        Matrix4.identity()
                          ..setEntry(
                            3,
                            2,
                            0.0018,
                          )
                          ..rotateX(
                            0.3,
                          )
                          ..rotateY(
                            angle,
                          )
                          ..rotateZ(
                            0.05,
                          ),

                    alignment:
                        Alignment.center,

                    child: Stack(
                      children: [
                        _buildFilePaneFace(
                          const Color(
                            0xFF89B4FA,
                          ),

                          Matrix4
                              .identity()
                            ..translate(
                              0.0,
                              0.0,
                              -3.0,
                            ),
                        ),

                        _buildFilePaneFace(
                          const Color(
                            0xFF89B4FA,
                          ),

                          Matrix4
                              .identity()
                            ..translate(
                              0.0,
                              0.0,
                              3.0,
                            ),

                          isFront: true,
                        ),
                      ],
                    ),
                  ),
          ),
        );
      },
    );
  }
}
