import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

Widget buildChariowOfferWidget() => FilledButton.icon(
  onPressed: () => launchUrl(
    Uri.parse('https://bizgestion.pages.dev/chariow-checkout.html'),
    mode: LaunchMode.externalApplication,
  ),
  icon: const Icon(Icons.open_in_new_rounded),
  label: const Text('Ouvrir le paiement Chariow'),
);
