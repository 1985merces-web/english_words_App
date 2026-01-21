import 'package:flutter/services.dart';

SystemUiOverlayStyle overlayStyleForTop({required bool darkTop}) {
  return SystemUiOverlayStyle(
    statusBarIconBrightness: darkTop ? Brightness.light : Brightness.dark,
    statusBarBrightness: darkTop ? Brightness.dark : Brightness.light,
  );
}
