BLUETOOTH SOURCE: NOT SWITCHED ON YET
=====================================

ble_sensor_source.dart.txt is the code that talks to the real insole. It is
kept here as a .txt file so the app and the tests ignore it. The app already
has a "Live" tab that works with a simulated insole; this code plugs into it.

It has NOT been tested: it was written from the package documentation without
an Android build or the insole.

To switch it on (do this together, once the Android setup works):
 1. Android Studio is installed and `flutter doctor` is happy.
 2. The Android phone is connected with a USB cable and `flutter devices`
    lists it.
 3. Add the package:  flutter pub add flutter_blue_plus
 4. Add the Bluetooth permissions to android/app/src/main/AndroidManifest.xml
    (the exact lines depend on the package version, so check its README).
 5. Rename ble_sensor_source.dart.txt to lib/services/ble_insole_source.dart
 6. In lib/screens/home_shell.dart, change the sourceBuilder line to use
    BleInsoleSource() instead of SimulatedInsoleSource(...).
 7. Run on the phone: flutter run  (not Chrome).
 8. Check that Chrome still builds: flutter run -d chrome

Test checklist with the insole:
 - Power the ESP32. It should advertise as SoleGuard-001.
 - Close nRF Connect on every other phone (only ONE phone can connect).
 - Press Connect on the Live tab. You should see a reading every second.
 - Switch off the ESP32 mid-way: the app should show "No data" and then a
   connection problem, not crash.
