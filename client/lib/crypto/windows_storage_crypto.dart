import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

// DPAPI protects bytes for the current Windows account. No shared plugin file.
String protectWindows(String value) =>
    base64Encode(_transform(utf8.encode(value), true));
String unprotectWindows(String value) =>
    utf8.decode(_transform(base64Decode(value), false));

Uint8List _transform(List<int> bytes, bool encrypt) => using((arena) {
  final data = arena<Uint8>(bytes.length);
  data.asTypedList(bytes.length).setAll(0, bytes);
  final input = arena<CRYPT_INTEGER_BLOB>();
  input.ref.cbData = bytes.length;
  input.ref.pbData = data;
  final output = arena<CRYPT_INTEGER_BLOB>();
  final result = encrypt
      ? CryptProtectData(
          input,
          nullptr,
          nullptr,
          nullptr,
          nullptr,
          1 /* CRYPTPROTECT_UI_FORBIDDEN */,
          output,
        )
      : CryptUnprotectData(
          input,
          nullptr,
          nullptr,
          nullptr,
          nullptr,
          1 /* CRYPTPROTECT_UI_FORBIDDEN */,
          output,
        );
  if (result == 0) {
    throw StateError('Windows key protection failed (${GetLastError()})');
  }
  try {
    return Uint8List.fromList(output.ref.pbData.asTypedList(output.ref.cbData));
  } finally {
    LocalFree(output.ref.pbData);
  }
});
