import 'package:flutter/material.dart';
import 'package:mykerawang/widgets/app_toast.dart';

/// `MaterialApp.builder` for tests that look for a pop-up message.
Widget withToasts(BuildContext context, Widget? child) =>
    AppToastHost(child: child!);
