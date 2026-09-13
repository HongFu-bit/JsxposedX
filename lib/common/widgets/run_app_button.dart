import 'package:JsxposedX/desktop/bridge/native_bridge.dart';
import 'package:flutter/material.dart';

class RunAppButton extends StatelessWidget {
  final VoidCallback? onClick;
  final String packageName;

  const RunAppButton({super.key, required this.packageName, this.onClick});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.play_arrow),
      tooltip: "run",
      onPressed: () {
        onClick?.call();
        NativeBridge.app.openAppX(packageName);
      },
    );
  }
}
