import 'dart:io';

import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

class ContactEntry {
  const ContactEntry({required this.displayName, required this.phoneNumber});

  final String displayName;
  final String phoneNumber;
}

class DeviceService {
  const DeviceService();

  Future<String?> captureAvatar() async {
    final cameraPermission = await Permission.camera.request();
    if (!cameraPermission.isGranted) {
      return null;
    }

    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
    );
    if (pickedFile == null) {
      return null;
    }

    final directory = await getApplicationDocumentsDirectory();
    final fileName = 'avatar_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final savedFile = await File(
      pickedFile.path,
    ).copy('${directory.path}/$fileName');
    return savedFile.path;
  }

  Future<List<ContactEntry>> loadContacts() async {
    final contactPermission = await Permission.contacts.request();
    if (!contactPermission.isGranted) {
      return [];
    }

    if (!await FlutterContacts.requestPermission(readonly: true)) {
      return [];
    }

    final contacts = await FlutterContacts.getContacts(withProperties: true);
    return contacts
        .where((contact) => contact.phones.isNotEmpty)
        .map(
          (contact) => ContactEntry(
            displayName: contact.displayName,
            phoneNumber: contact.phones.first.number,
          ),
        )
        .toList(growable: false);
  }

  Future<bool> openSms(String phoneNumber, {required String message}) async {
    final uri = Uri.parse(
      'sms:$phoneNumber?body=${Uri.encodeComponent(message)}',
    );
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
