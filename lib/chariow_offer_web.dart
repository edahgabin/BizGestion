import 'dart:html' as html;

import 'package:flutter/material.dart';

Widget buildChariowOfferWidget() => FilledButton.icon(
  onPressed: () {
    final checkoutPage = Uri.base.resolve('/chariow-checkout.html');
    html.window.location.assign(checkoutPage.toString());
  },
  icon: const Icon(Icons.open_in_new_rounded),
  label: const Text('Ouvrir le paiement Chariow'),
);
