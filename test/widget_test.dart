import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bizgestion/main.dart';

void main() {
  testWidgets('l’écran de connexion affiche les champs principaux', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AuthPage()));

    expect(find.text('Bienvenue sur BizGestion'), findsOneWidget);
    expect(find.text('Adresse e-mail'), findsOneWidget);
    expect(find.text('Mot de passe'), findsOneWidget);
    expect(find.text('Se connecter'), findsOneWidget);
  });
}
