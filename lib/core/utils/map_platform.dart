import 'package:flutter/foundation.dart';

bool get usesGoogleMaps => kIsWeb || defaultTargetPlatform == TargetPlatform.android;
