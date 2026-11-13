import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/services.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

import 'data_transfer.dart';
import 'offline_events_stub.dart'
    if (dart.library.html) 'offline_events_web.dart';
import 'chariow_offer_stub.dart'
    if (dart.library.html) 'chariow_offer_web.dart';

import 'package:mobile_scanner/mobile_scanner.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'https://kxrmmyhqjvihrabmmgoa.supabase.co',
    publishableKey: 'sb_publishable_fwRuCkR4gY_N_5n_10uLNw_OjOF8pH5',
  );
  runApp(const BizGestionApp());
}

const teal = Color(0xFF087F78);
const navy = Color(0xFF202C82);
const ink = Color(0xFF24333B);
const background = Color(0xFFF4F6FB);
const bool _paypalSandboxCheckoutEnabled = bool.fromEnvironment(
  'PAYPAL_SANDBOX_ENABLED',
  defaultValue: false,
);
const bool _paypalLiveCheckoutEnabled = bool.fromEnvironment(
  'PAYPAL_LIVE_ENABLED',
  defaultValue: false,
);
const bool _paypalCheckoutEnabled =
    _paypalSandboxCheckoutEnabled != _paypalLiveCheckoutEnabled;
const _googlePlaySubscriptionProducts = <String>{
  'bizgestion_commerce_monthly',
  'bizgestion_commerce_annual',
  'bizgestion_entreprise_monthly',
  'bizgestion_entreprise_annual',
};

// Country settings apply at the commerce level. The default remains Benin/XOF
// so existing businesses keep their current monetary interpretation.
String _activeCountryCode = 'BJ';
String _activeCurrencyCode = 'XOF';
String _activeLanguageCode = 'fr';
final ValueNotifier<Locale> _appLocale = ValueNotifier(const Locale('fr'));

/// The shared entry point for every user-facing interface string.
/// Add both French and English text here at each new UI label; user-entered
/// business data (product/customer names, notes, etc.) must remain untouched.
String _tr(String french, String english) =>
    _activeLanguageCode == 'en' ? english : french;

void _setActiveLanguage(String languageCode) {
  _activeLanguageCode = languageCode == 'en' ? 'en' : 'fr';
  final locale = Locale(_activeLanguageCode);
  if (_appLocale.value != locale) _appLocale.value = locale;
}

String _localizedSyncError(String message) => switch (message) {
  'Enregistrement cloud impossible. Ta dernière modification est gardée sur cet appareil; vérifie la connexion et les tables Supabase.' =>
    _tr(
      message,
      'Cloud save failed. Your latest change is saved on this device. Check your connection and Supabase setup.',
    ),
  'Le cloud BizGestion n’est pas encore prêt. Vérifie le script SQL Supabase; en attendant, les données restent sur cet appareil.' =>
    _tr(
      message,
      'BizGestion cloud is not ready yet. Check the Supabase SQL setup; your data remains saved on this device for now.',
    ),
  'Connexion cloud indisponible. Les données enregistrées sur cet appareil restent accessibles; réessaie quand Internet revient.' =>
    _tr(
      message,
      'Cloud connection unavailable. Data saved on this device is still available; try again when the internet is back.',
    ),
  'Aucun commerce cloud n’est associé à ce compte. Les données restent enregistrées sur cet appareil.' =>
    _tr(
      message,
      'No cloud business is linked to this account. Your data remains saved on this device.',
    ),
  _ => message,
};

String _localizedPageName(String frenchName) => switch (frenchName) {
  'Accueil' => _tr('Accueil', 'Home'),
  'Ventes' => _tr('Ventes', 'Sales'),
  'Achats' => _tr('Achats', 'Purchases'),
  'Stock' => _tr('Stock', 'Inventory'),
  'Clients' => _tr('Clients', 'Customers'),
  'Dépenses' => _tr('Dépenses', 'Expenses'),
  'Rapports' => _tr('Rapports', 'Reports'),
  'Caisse' => _tr('Caisse', 'Cash register'),
  _ => frenchName,
};

String _periodLabel(String frenchPeriod) => switch (frenchPeriod) {
  'Aujourd’hui' => _tr('Aujourd’hui', 'Today'),
  'Cette semaine' => _tr('Cette semaine', 'This week'),
  'Ce mois' => _tr('Ce mois', 'This month'),
  'Cette année' => _tr('Cette année', 'This year'),
  'Tout' => _tr('Tout', 'All time'),
  '7 derniers jours' => _tr('7 derniers jours', 'Last 7 days'),
  _ => frenchPeriod,
};

String _paymentMethodLabel(String method) => switch (method) {
  'Espèces' => _tr('Espèces', 'Cash'),
  'Banque' => _tr('Banque', 'Bank'),
  'Autre' => _tr('Autre', 'Other'),
  'Crédit fournisseur' => _tr('Crédit fournisseur', 'Supplier credit'),
  'Non précisé' => _tr('Non précisé', 'Unspecified'),
  _ => method,
};

String _pickupStatusLabel(String status) => switch (status) {
  'À retirer' => _tr('À retirer', 'Ready for pickup'),
  'Retiré' => _tr('Retiré', 'Collected'),
  'Remis au client' => _tr('Remis au client', 'Handed to customer'),
  _ => status,
};

String _unitLabel(String unit) => switch (unit.trim().toLowerCase()) {
  'pièce' || 'piece' || 'unité' || 'unit' => _tr('Pièce', 'Piece'),
  'kg' || 'kilogramme' || 'kilogrammes' => 'kg',
  'g' || 'gramme' || 'grammes' => 'g',
  'litre' || 'litres' || 'l' => 'L',
  'bidon' => _tr('Bidon', 'Can'),
  'sac' => _tr('Sac', 'Bag'),
  'sachet' => _tr('Sachet', 'Small bag'),
  'carton' => _tr('Carton', 'Box'),
  'boîte' || 'boite' => _tr('Boîte', 'Box'),
  'bouteille' => _tr('Bouteille', 'Bottle'),
  'paquet' => _tr('Paquet', 'Pack'),
  'plastique' => _tr('Plastique', 'Plastic bottle'),
  'fût' || 'fut' => _tr('Fût', 'Drum'),
  'palette' => _tr('Palette', 'Pallet'),
  'tonne' => _tr('Tonne', 'Tonne'),
  'rouleau' => _tr('Rouleau', 'Roll'),
  _ => unit,
};

const _commonProductUnits = <String>[
  'Sac',
  'Carton',
  'Caisse',
  'Bidon',
  'Plastique',
  'Sachet',
  'Bouteille',
  'Paquet',
  'Boîte',
  'Pièce',
  'Kg',
  'g',
  'Litre',
  'mL',
  'Soghor',
  'Fût',
  'Palette',
  'Tonne',
  'Rouleau',
  'Douzaine',
];
const _customProductUnitValue = '__bizgestion_custom_unit__';

List<DropdownMenuItem<String>> _productUnitItems({
  Iterable<String> extraUnits = const [],
}) {
  final units = <String>{..._commonProductUnits, ...extraUnits};
  return [
    ...units.map(
      (value) => DropdownMenuItem(value: value, child: Text(_unitLabel(value))),
    ),
    DropdownMenuItem(
      value: _customProductUnitValue,
      child: Text(_tr('Autre unité…', 'Other unit…')),
    ),
  ];
}

String _categoryLabel(String category) =>
    switch (category.trim().toLowerCase()) {
      'alimentation' => _tr('Alimentation', 'Food'),
      'boissons' => _tr('Boissons', 'Beverages'),
      'hygiène' || 'hygiene' => _tr('Hygiène', 'Personal care'),
      'entretien' => _tr('Entretien', 'Cleaning'),
      'vêtements' || 'vetements' => _tr('Vêtements', 'Clothing'),
      'électronique' || 'electronique' => _tr('Électronique', 'Electronics'),
      'cosmétiques' || 'cosmetiques' => _tr('Cosmétiques', 'Beauty'),
      'autre' => _tr('Autre', 'Other'),
      _ => category,
    };

String _formatCustomerName(String value) {
  return value
      .split(RegExp(r'\s+'))
      .map(
        (part) => part.replaceAllMapped(
          RegExp(r"(^|[-'’])([A-Za-zÀ-ÖØ-öø-ÿ])"),
          (match) => '${match.group(1)}${match.group(2)!.toUpperCase()}',
        ),
      )
      .join(' ');
}

String _customerLabel(String name) =>
    name.trim().toLowerCase() == 'client comptant'
    ? _tr('Client comptant', 'Cash customer')
    : _formatCustomerName(name);

String _customerFilterLabel(String filter) => switch (filter) {
  'Tous' => _tr('Tous', 'All'),
  'À recouvrer' => _tr('À recouvrer', 'Outstanding'),
  'En retard' => _tr('En retard', 'Overdue'),
  'Soldés' => _tr('Soldés', 'Paid'),
  _ => filter,
};

String _teamRoleLabel(String role) => switch (role) {
  'owner' => _tr('Propriétaire', 'Owner'),
  'admin' => _tr('Administrateur', 'Administrator'),
  _ => _tr('Employé', 'Staff'),
};

String _teamStatusLabel(String status) => switch (status) {
  'Membre' => _tr('Membre', 'Member'),
  'Invitation en attente' => _tr('Invitation en attente', 'Invitation pending'),
  'Compte en attente de confirmation' => _tr(
    'Compte en attente de confirmation',
    'Account awaiting confirmation',
  ),
  _ => status,
};

class _MarketOption {
  const _MarketOption(
    this.countryCode,
    this.countryName,
    this.currencyCode,
    this.currencyName,
    this.englishCountryName,
  );
  final String countryCode;
  final String countryName;
  final String currencyCode;
  final String currencyName;
  final String englishCountryName;
  String get label => labelFor(_activeLanguageCode);
  String labelFor(String languageCode) => languageCode == 'en'
      ? '$englishCountryName • $currencyCode'
      : '$countryName • $currencyCode ($currencyName)';
}

const _marketOptions = <_MarketOption>[
  // West and Central Africa
  _MarketOption('BJ', 'Bénin', 'XOF', 'Franc CFA BCEAO', 'Benin'),
  _MarketOption('BF', 'Burkina Faso', 'XOF', 'Franc CFA BCEAO', 'Burkina Faso'),
  _MarketOption(
    'CI',
    'Côte d’Ivoire',
    'XOF',
    'Franc CFA BCEAO',
    'Côte d’Ivoire',
  ),
  _MarketOption(
    'GW',
    'Guinée-Bissau',
    'XOF',
    'Franc CFA BCEAO',
    'Guinea-Bissau',
  ),
  _MarketOption('ML', 'Mali', 'XOF', 'Franc CFA BCEAO', 'Mali'),
  _MarketOption('NE', 'Niger', 'XOF', 'Franc CFA BCEAO', 'Niger'),
  _MarketOption('SN', 'Sénégal', 'XOF', 'Franc CFA BCEAO', 'Senegal'),
  _MarketOption('TG', 'Togo', 'XOF', 'Franc CFA BCEAO', 'Togo'),
  _MarketOption('GH', 'Ghana', 'GHS', 'Cedi ghanéen', 'Ghana'),
  _MarketOption('GN', 'Guinée', 'GNF', 'Franc guinéen', 'Guinea'),
  _MarketOption('NG', 'Nigeria', 'NGN', 'Naira', 'Nigeria'),
  _MarketOption('CM', 'Cameroun', 'XAF', 'Franc CFA BEAC', 'Cameroon'),
  _MarketOption('GA', 'Gabon', 'XAF', 'Franc CFA BEAC', 'Gabon'),
  _MarketOption('CD', 'R.D. Congo', 'CDF', 'Franc congolais', 'DR Congo'),
  _MarketOption('AO', 'Angola', 'AOA', 'Kwanza', 'Angola'),
  _MarketOption('DZ', 'Algérie', 'DZD', 'Dinar algérien', 'Algeria'),
  _MarketOption('CV', 'Cap-Vert', 'CVE', 'Escudo cap-verdien', 'Cabo Verde'),
  _MarketOption(
    'CF',
    'République centrafricaine',
    'XAF',
    'Franc CFA BEAC',
    'Central African Republic',
  ),
  _MarketOption('TD', 'Tchad', 'XAF', 'Franc CFA BEAC', 'Chad'),
  _MarketOption(
    'CG',
    'Congo',
    'XAF',
    'Franc CFA BEAC',
    'Republic of the Congo',
  ),
  _MarketOption(
    'GQ',
    'Guinée équatoriale',
    'XAF',
    'Franc CFA BEAC',
    'Equatorial Guinea',
  ),
  _MarketOption('MA', 'Maroc', 'MAD', 'Dirham marocain', 'Morocco'),
  _MarketOption('MR', 'Mauritanie', 'MRU', 'Ouguiya', 'Mauritania'),
  _MarketOption('GM', 'Gambie', 'GMD', 'Dalasi', 'Gambia'),
  _MarketOption('SL', 'Sierra Leone', 'SLE', 'Leone', 'Sierra Leone'),
  _MarketOption('LR', 'Libéria', 'LRD', 'Dollar libérien', 'Liberia'),
  _MarketOption('ET', 'Éthiopie', 'ETB', 'Birr', 'Ethiopia'),
  _MarketOption('KE', 'Kenya', 'KES', 'Shilling kényan', 'Kenya'),
  _MarketOption('TZ', 'Tanzanie', 'TZS', 'Shilling tanzanien', 'Tanzania'),
  _MarketOption('UG', 'Ouganda', 'UGX', 'Shilling ougandais', 'Uganda'),
  _MarketOption('RW', 'Rwanda', 'RWF', 'Franc rwandais', 'Rwanda'),
  _MarketOption('BI', 'Burundi', 'BIF', 'Franc burundais', 'Burundi'),
  _MarketOption('DJ', 'Djibouti', 'DJF', 'Franc djiboutien', 'Djibouti'),
  _MarketOption('SO', 'Somalie', 'SOS', 'Shilling somalien', 'Somalia'),
  _MarketOption('ER', 'Érythrée', 'ERN', 'Nakfa', 'Eritrea'),
  _MarketOption(
    'SS',
    'Soudan du Sud',
    'SSP',
    'Livre sud-soudanaise',
    'South Sudan',
  ),
  _MarketOption('SD', 'Soudan', 'SDG', 'Livre soudanaise', 'Sudan'),
  _MarketOption('EG', 'Égypte', 'EGP', 'Livre égyptienne', 'Egypt'),
  _MarketOption('LY', 'Libye', 'LYD', 'Dinar libyen', 'Libya'),
  _MarketOption('TN', 'Tunisie', 'TND', 'Dinar tunisien', 'Tunisia'),
  _MarketOption('ZA', 'Afrique du Sud', 'ZAR', 'Rand', 'South Africa'),
  _MarketOption('BW', 'Botswana', 'BWP', 'Pula', 'Botswana'),
  _MarketOption('NA', 'Namibie', 'NAD', 'Dollar namibien', 'Namibia'),
  _MarketOption('ZM', 'Zambie', 'ZMW', 'Kwacha zambien', 'Zambia'),
  _MarketOption('ZW', 'Zimbabwe', 'ZWG', 'Zimbabwe Gold', 'Zimbabwe'),
  _MarketOption('MZ', 'Mozambique', 'MZN', 'Metical', 'Mozambique'),
  _MarketOption('MG', 'Madagascar', 'MGA', 'Ariary', 'Madagascar'),
  _MarketOption('MU', 'Maurice', 'MUR', 'Roupie mauricienne', 'Mauritius'),
  _MarketOption('SC', 'Seychelles', 'SCR', 'Roupie seychelloise', 'Seychelles'),
  _MarketOption('KM', 'Comores', 'KMF', 'Franc comorien', 'Comoros'),
  _MarketOption('SZ', 'Eswatini', 'SZL', 'Lilangeni', 'Eswatini'),
  _MarketOption('LS', 'Lesotho', 'LSL', 'Loti', 'Lesotho'),
  _MarketOption('MW', 'Malawi', 'MWK', 'Kwacha malawien', 'Malawi'),
  _MarketOption(
    'ST',
    'Sao Tomé-et-Principe',
    'STN',
    'Dobra',
    'São Tomé and Príncipe',
  ),

  // Europe
  _MarketOption('FR', 'France', 'EUR', 'Euro', 'France'),
  _MarketOption('DE', 'Allemagne', 'EUR', 'Euro', 'Germany'),
  _MarketOption('GB', 'Royaume-Uni', 'GBP', 'Livre sterling', 'United Kingdom'),
  _MarketOption('CH', 'Suisse', 'CHF', 'Franc suisse', 'Switzerland'),
  _MarketOption('IT', 'Italie', 'EUR', 'Euro', 'Italy'),
  _MarketOption('ES', 'Espagne', 'EUR', 'Euro', 'Spain'),
  _MarketOption('PT', 'Portugal', 'EUR', 'Euro', 'Portugal'),
  _MarketOption('BE', 'Belgique', 'EUR', 'Euro', 'Belgium'),
  _MarketOption('NL', 'Pays-Bas', 'EUR', 'Euro', 'Netherlands'),
  _MarketOption('AT', 'Autriche', 'EUR', 'Euro', 'Austria'),
  _MarketOption('IE', 'Irlande', 'EUR', 'Euro', 'Ireland'),
  _MarketOption('SE', 'Suède', 'SEK', 'Couronne suédoise', 'Sweden'),
  _MarketOption('NO', 'Norvège', 'NOK', 'Couronne norvégienne', 'Norway'),
  _MarketOption('DK', 'Danemark', 'DKK', 'Couronne danoise', 'Denmark'),
  _MarketOption('PL', 'Pologne', 'PLN', 'Zloty', 'Poland'),
  _MarketOption('CZ', 'Tchéquie', 'CZK', 'Couronne tchèque', 'Czechia'),
  _MarketOption('RO', 'Roumanie', 'RON', 'Leu roumain', 'Romania'),
  _MarketOption('HU', 'Hongrie', 'HUF', 'Forint', 'Hungary'),
  _MarketOption('GR', 'Grèce', 'EUR', 'Euro', 'Greece'),
  _MarketOption('BG', 'Bulgarie', 'EUR', 'Euro', 'Bulgaria'),
  _MarketOption('HR', 'Croatie', 'EUR', 'Euro', 'Croatia'),
  _MarketOption('UA', 'Ukraine', 'UAH', 'Hryvnia', 'Ukraine'),
  _MarketOption('RU', 'Russie', 'RUB', 'Rouble russe', 'Russia'),
  _MarketOption('TR', 'Turquie', 'TRY', 'Livre turque', 'Türkiye'),
  _MarketOption('IS', 'Islande', 'ISK', 'Couronne islandaise', 'Iceland'),
  _MarketOption('RS', 'Serbie', 'RSD', 'Dinar serbe', 'Serbia'),
  _MarketOption(
    'BA',
    'Bosnie-Herzégovine',
    'BAM',
    'Mark convertible',
    'Bosnia and Herzegovina',
  ),
  _MarketOption('AL', 'Albanie', 'ALL', 'Lek', 'Albania'),
  _MarketOption('MK', 'Macédoine du Nord', 'MKD', 'Denar', 'North Macedonia'),
  _MarketOption('MD', 'Moldavie', 'MDL', 'Leu moldave', 'Moldova'),
  _MarketOption('GE', 'Géorgie', 'GEL', 'Lari', 'Georgia'),
  _MarketOption('AM', 'Arménie', 'AMD', 'Dram', 'Armenia'),
  _MarketOption(
    'AZ',
    'Azerbaïdjan',
    'AZN',
    'Manat azerbaïdjanais',
    'Azerbaijan',
  ),

  // Americas and Caribbean
  _MarketOption('US', 'États-Unis', 'USD', 'Dollar américain', 'United States'),
  _MarketOption('CA', 'Canada', 'CAD', 'Dollar canadien', 'Canada'),
  _MarketOption('MX', 'Mexique', 'MXN', 'Peso mexicain', 'Mexico'),
  _MarketOption('BR', 'Brésil', 'BRL', 'Réal brésilien', 'Brazil'),
  _MarketOption('AR', 'Argentine', 'ARS', 'Peso argentin', 'Argentina'),
  _MarketOption('CL', 'Chili', 'CLP', 'Peso chilien', 'Chile'),
  _MarketOption('CO', 'Colombie', 'COP', 'Peso colombien', 'Colombia'),
  _MarketOption('PE', 'Pérou', 'PEN', 'Sol', 'Peru'),
  _MarketOption('UY', 'Uruguay', 'UYU', 'Peso uruguayen', 'Uruguay'),
  _MarketOption('PY', 'Paraguay', 'PYG', 'Guarani', 'Paraguay'),
  _MarketOption('BO', 'Bolivie', 'BOB', 'Boliviano', 'Bolivia'),
  _MarketOption('EC', 'Équateur', 'USD', 'Dollar américain', 'Ecuador'),
  _MarketOption('VE', 'Venezuela', 'VES', 'Bolivar', 'Venezuela'),
  _MarketOption('CR', 'Costa Rica', 'CRC', 'Colón costaricien', 'Costa Rica'),
  _MarketOption('PA', 'Panama', 'PAB', 'Balboa', 'Panama'),
  _MarketOption(
    'DO',
    'République dominicaine',
    'DOP',
    'Peso dominicain',
    'Dominican Republic',
  ),
  _MarketOption(
    'TT',
    'Trinité-et-Tobago',
    'TTD',
    'Dollar de Trinité-et-Tobago',
    'Trinidad and Tobago',
  ),
  _MarketOption('BS', 'Bahamas', 'BSD', 'Dollar bahaméen', 'Bahamas'),
  _MarketOption('BB', 'Barbade', 'BBD', 'Dollar barbadien', 'Barbados'),
  _MarketOption('BZ', 'Belize', 'BZD', 'Dollar bélizien', 'Belize'),
  _MarketOption('GT', 'Guatemala', 'GTQ', 'Quetzal', 'Guatemala'),
  _MarketOption('HN', 'Honduras', 'HNL', 'Lempira', 'Honduras'),
  _MarketOption('SV', 'Salvador', 'USD', 'Dollar américain', 'El Salvador'),
  _MarketOption('NI', 'Nicaragua', 'NIO', 'Córdoba', 'Nicaragua'),
  _MarketOption('GY', 'Guyana', 'GYD', 'Dollar du Guyana', 'Guyana'),
  _MarketOption('SR', 'Suriname', 'SRD', 'Dollar surinamais', 'Suriname'),
  _MarketOption('HT', 'Haïti', 'HTG', 'Gourde', 'Haiti'),
  _MarketOption('CU', 'Cuba', 'CUP', 'Peso cubain', 'Cuba'),
  _MarketOption('JM', 'Jamaïque', 'JMD', 'Dollar jamaïcain', 'Jamaica'),
  _MarketOption(
    'AG',
    'Antigua-et-Barbuda',
    'XCD',
    'Dollar des Caraïbes orientales',
    'Antigua and Barbuda',
  ),
  _MarketOption(
    'GD',
    'Grenade',
    'XCD',
    'Dollar des Caraïbes orientales',
    'Grenada',
  ),
  _MarketOption(
    'LC',
    'Sainte-Lucie',
    'XCD',
    'Dollar des Caraïbes orientales',
    'Saint Lucia',
  ),

  // Asia and the Middle East
  _MarketOption('CN', 'Chine', 'CNY', 'Yuan', 'China'),
  _MarketOption('JP', 'Japon', 'JPY', 'Yen', 'Japan'),
  _MarketOption('IN', 'Inde', 'INR', 'Roupie indienne', 'India'),
  _MarketOption('PK', 'Pakistan', 'PKR', 'Roupie pakistanaise', 'Pakistan'),
  _MarketOption('BD', 'Bangladesh', 'BDT', 'Taka', 'Bangladesh'),
  _MarketOption('LK', 'Sri Lanka', 'LKR', 'Roupie sri-lankaise', 'Sri Lanka'),
  _MarketOption('NP', 'Népal', 'NPR', 'Roupie népalaise', 'Nepal'),
  _MarketOption('VN', 'Viêt Nam', 'VND', 'Dong', 'Vietnam'),
  _MarketOption('ID', 'Indonésie', 'IDR', 'Roupie indonésienne', 'Indonesia'),
  _MarketOption('MY', 'Malaisie', 'MYR', 'Ringgit', 'Malaysia'),
  _MarketOption('SG', 'Singapour', 'SGD', 'Dollar de Singapour', 'Singapore'),
  _MarketOption('PH', 'Philippines', 'PHP', 'Peso philippin', 'Philippines'),
  _MarketOption('KR', 'Corée du Sud', 'KRW', 'Won sud-coréen', 'South Korea'),
  _MarketOption('TW', 'Taïwan', 'TWD', 'Nouveau dollar taïwanais', 'Taiwan'),
  _MarketOption('HK', 'Hong Kong', 'HKD', 'Dollar de Hong Kong', 'Hong Kong'),
  _MarketOption('KH', 'Cambodge', 'KHR', 'Riel', 'Cambodia'),
  _MarketOption('MM', 'Myanmar', 'MMK', 'Kyat', 'Myanmar'),
  _MarketOption('MN', 'Mongolie', 'MNT', 'Tugrik', 'Mongolia'),
  _MarketOption('KZ', 'Kazakhstan', 'KZT', 'Tenge', 'Kazakhstan'),
  _MarketOption('TH', 'Thaïlande', 'THB', 'Baht', 'Thailand'),
  _MarketOption(
    'SA',
    'Arabie saoudite',
    'SAR',
    'Riyal saoudien',
    'Saudi Arabia',
  ),
  _MarketOption(
    'AE',
    'Émirats arabes unis',
    'AED',
    'Dirham des Émirats',
    'United Arab Emirates',
  ),
  _MarketOption('QA', 'Qatar', 'QAR', 'Riyal qatari', 'Qatar'),
  _MarketOption('KW', 'Koweït', 'KWD', 'Dinar koweïtien', 'Kuwait'),
  _MarketOption('BH', 'Bahreïn', 'BHD', 'Dinar bahreïni', 'Bahrain'),
  _MarketOption('OM', 'Oman', 'OMR', 'Rial omanais', 'Oman'),
  _MarketOption('JO', 'Jordanie', 'JOD', 'Dinar jordanien', 'Jordan'),
  _MarketOption('IL', 'Israël', 'ILS', 'Nouveau shekel', 'Israel'),
  _MarketOption('LB', 'Liban', 'LBP', 'Livre libanaise', 'Lebanon'),
  _MarketOption('IQ', 'Irak', 'IQD', 'Dinar irakien', 'Iraq'),
  _MarketOption('IR', 'Iran', 'IRR', 'Rial iranien', 'Iran'),
  _MarketOption('AF', 'Afghanistan', 'AFN', 'Afghani', 'Afghanistan'),
  _MarketOption('UZ', 'Ouzbékistan', 'UZS', 'Sum ouzbek', 'Uzbekistan'),

  // Oceania
  _MarketOption('AU', 'Australie', 'AUD', 'Dollar australien', 'Australia'),
  _MarketOption(
    'NZ',
    'Nouvelle-Zélande',
    'NZD',
    'Dollar néo-zélandais',
    'New Zealand',
  ),
  _MarketOption('FJ', 'Fidji', 'FJD', 'Dollar fidjien', 'Fiji'),
  _MarketOption(
    'PG',
    'Papouasie-Nouvelle-Guinée',
    'PGK',
    'Kina',
    'Papua New Guinea',
  ),
  _MarketOption('WS', 'Samoa', 'WST', 'Tala', 'Samoa'),
  _MarketOption('TO', 'Tonga', 'TOP', 'Paʻanga', 'Tonga'),
  _MarketOption('VU', 'Vanuatu', 'VUV', 'Vatu', 'Vanuatu'),
  _MarketOption(
    'SB',
    'Îles Salomon',
    'SBD',
    'Dollar des Salomon',
    'Solomon Islands',
  ),
  _MarketOption('KI', 'Kiribati', 'AUD', 'Dollar australien', 'Kiribati'),
  _MarketOption('TV', 'Tuvalu', 'AUD', 'Dollar australien', 'Tuvalu'),
  _MarketOption('NR', 'Nauru', 'AUD', 'Dollar australien', 'Nauru'),
  _MarketOption('PW', 'Palaos', 'USD', 'Dollar américain', 'Palau'),
  _MarketOption(
    'MH',
    'Îles Marshall',
    'USD',
    'Dollar américain',
    'Marshall Islands',
  ),
  _MarketOption(
    'FM',
    'États fédérés de Micronésie',
    'USD',
    'Dollar américain',
    'Federated States of Micronesia',
  ),
];

String get _currencyLabel => switch (_activeCurrencyCode) {
  'XOF' || 'XAF' => 'FCFA',
  'GNF' => 'GNF',
  'GHS' => 'GHS',
  'NGN' => 'NGN',
  'CDF' => 'CDF',
  'EUR' => 'EUR',
  'USD' => 'USD',
  _ => _activeCurrencyCode,
};

String _newRecordId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

class BizGestionApp extends StatelessWidget {
  const BizGestionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: _appLocale,
      builder: (context, locale, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'BizGestion',
        locale: locale,
        supportedLocales: const [Locale('fr'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: ThemeData(
          useMaterial3: true,
          scaffoldBackgroundColor: background,
          colorScheme: ColorScheme.fromSeed(seedColor: navy)
              .copyWith(secondary: teal),
          fontFamily: 'Roboto',
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.white,
            foregroundColor: ink,
            elevation: 0,
            centerTitle: false,
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              backgroundColor: navy,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
            ),
          ),
          navigationBarTheme: NavigationBarThemeData(
            backgroundColor: Colors.white,
            indicatorColor: const Color(0xFFE8EAFE),
            labelTextStyle: WidgetStateProperty.resolveWith(
              (states) => TextStyle(
                color: states.contains(WidgetState.selected)
                    ? navy
                    : const Color(0xFF68717E),
                fontWeight: states.contains(WidgetState.selected)
                    ? FontWeight.w700
                    : FontWeight.w500,
              ),
            ),
          ),
          cardTheme: CardThemeData(
            color: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: const BorderSide(color: Color(0xFFE5E9F2)),
            ),
          ),
          navigationRailTheme: NavigationRailThemeData(
            backgroundColor: Colors.white,
            indicatorColor: const Color(0xFFE8EAFE),
            selectedIconTheme: const IconThemeData(color: navy),
            selectedLabelTextStyle: const TextStyle(
              color: navy,
              fontWeight: FontWeight.w700,
            ),
            unselectedIconTheme: const IconThemeData(color: Color(0xFF68717E)),
            unselectedLabelTextStyle: const TextStyle(color: Color(0xFF68717E)),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFDDE2EC)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: navy, width: 1.5),
            ),
          ),
        ),
        home: const AuthGate(),
      ),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final client = Supabase.instance.client;
    return StreamBuilder<AuthState>(
      stream: client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = snapshot.data?.session ?? client.auth.currentSession;
        if (session == null) return const AuthPage();
        return DashboardPage(
          userId: session.user.id,
          email: session.user.email ?? '',
        );
      },
    );
  }
}

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _formKey = GlobalKey<FormState>();
  final _businessNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _creatingAccount = false;
  bool _invitedSignup = false;
  bool _loading = false;
  bool _obscurePassword = true;
  _MarketOption? _signupMarket;
  String? _message;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) return;
    final query = Uri.base.queryParameters;
    final inviteLanguage = query['lang'];
    if (inviteLanguage == 'en' || inviteLanguage == 'fr') {
      _setActiveLanguage(inviteLanguage!);
    }
    final inviteEmail = query['invite'];
    if (inviteEmail != null && inviteEmail.contains('@')) {
      _emailController.text = inviteEmail;
      _creatingAccount = query['create'] == '1';
      _invitedSignup = true;
    }
  }

  @override
  void dispose() {
    _businessNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading) return;
    if (_creatingAccount && !_invitedSignup && _signupMarket == null) {
      setState(() {
        _error = _tr(
          'Choisis la région où se trouve ton commerce pour définir la devise.',
          'Choose your business region to set its currency.',
        );
        _message = null;
      });
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _message = null;
      _error = null;
    });
    try {
      final auth = Supabase.instance.client.auth;
      if (_creatingAccount) {
        final userMetadata = <String, dynamic>{
          'business_name': _businessNameController.text.trim(),
          'language_code': _activeLanguageCode,
        };
        if (!_invitedSignup && _signupMarket != null) {
          userMetadata['country_code'] = _signupMarket!.countryCode;
          userMetadata['currency_code'] = _signupMarket!.currencyCode;
        }
        final response = await auth.signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          emailRedirectTo: kIsWeb ? Uri.base.origin : null,
          data: userMetadata,
        );
        if (response.session == null && mounted) {
          setState(
            () => _message = _tr(
              'Compte créé. Confirme ton adresse depuis le lien reçu : tu reviendras automatiquement dans BizGestion. Si tu as été invité, le commerce partagé sera déjà associé à ton compte.',
              'Account created. Confirm your email using the link we sent. You will then return to BizGestion. If you were invited, your shared business will already be linked to your account.',
            ),
          );
        }
      } else {
        await auth.signInWithPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
      }
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted)
        setState(
          () => _error = _tr(
            'Connexion impossible. Vérifie ta connexion Internet puis réessaie.',
            'Could not connect. Check your internet connection and try again.',
          ),
        );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Card(
              color: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                side: const BorderSide(color: Color(0xFFE4E9EB)),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Image.asset(
                        'assets/branding/bizgestion-logo.png',
                        width: 180,
                        height: 180,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _creatingAccount
                            ? _tr('Créer mon compte', 'Create your account')
                            : _tr('Bienvenue', 'Welcome'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: ink,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _creatingAccount
                            ? _tr(
                                'Commence à gérer ton commerce.',
                                'Start managing your business.',
                              )
                            : _tr(
                                'Connecte-toi pour accéder à ton espace.',
                                'Sign in to access your workspace.',
                              ),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.black54),
                      ),
                      const SizedBox(height: 28),
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: _tr('Adresse e-mail', 'Email address'),
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) =>
                            value == null || !value.contains('@')
                            ? _tr(
                                'Saisis une adresse e-mail valide.',
                                'Enter a valid email address.',
                              )
                            : null,
                      ),
                      if (_creatingAccount) ...[
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _businessNameController,
                          textCapitalization: TextCapitalization.words,
                          decoration: InputDecoration(
                            labelText: _tr(
                              'Nom du commerce (facultatif si tu es invité)',
                              'Business name (optional if you were invited)',
                            ),
                            helperText: _tr(
                              'Pour une invitation, laisse ce champ vide : le commerce partagé sera ouvert automatiquement.',
                              'If you were invited, leave this blank. Your shared business will open automatically.',
                            ),
                            border: OutlineInputBorder(),
                          ),
                        ),
                        if (!_invitedSignup) ...[
                          const SizedBox(height: 16),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              _tr('Région du commerce', 'Business region'),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: ink,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _loading ? null : _chooseSignupMarket,
                              icon: const Icon(Icons.public_outlined),
                              label: Text(
                                _signupMarket?.labelFor(_activeLanguageCode) ??
                                    _tr('Choisir un pays', 'Choose a country'),
                              ),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 16,
                                ),
                                alignment: Alignment.centerLeft,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              _signupMarket == null
                                  ? _tr(
                                      'La devise de ton commerce sera réglée automatiquement selon ce choix.',
                                      'Your business currency will be set automatically from this choice.',
                                    )
                                  : _tr(
                                      'Devise appliquée dès la création : ${_signupMarket!.currencyCode} (${_signupMarket!.currencyName}).',
                                      'Currency applied as soon as the business is created: ${_signupMarket!.currencyCode} (${_signupMarket!.currencyName}).',
                                    ),
                              style: const TextStyle(
                                color: Colors.black54,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ],
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _submit(),
                        decoration: InputDecoration(
                          labelText: _tr('Mot de passe', 'Password'),
                          border: OutlineInputBorder(),
                          suffixIcon: IconButton(
                            tooltip: _obscurePassword
                                ? _tr(
                                    'Afficher le mot de passe',
                                    'Show password',
                                  )
                                : _tr(
                                    'Masquer le mot de passe',
                                    'Hide password',
                                  ),
                            onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword,
                            ),
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                            ),
                          ),
                        ),
                        validator: (value) => value == null || value.length < 8
                            ? _tr(
                                'Utilise au moins 8 caractères.',
                                'Use at least 8 characters.',
                              )
                            : null,
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 14),
                        Text(
                          _error!,
                          style: const TextStyle(color: Colors.red),
                          textAlign: TextAlign.center,
                        ),
                      ],
                      if (_message != null) ...[
                        const SizedBox(height: 14),
                        Text(
                          _message!,
                          style: const TextStyle(color: teal),
                          textAlign: TextAlign.center,
                        ),
                      ],
                      const SizedBox(height: 22),
                      FilledButton(
                        onPressed: _loading ? null : _submit,
                        style: FilledButton.styleFrom(
                          backgroundColor: teal,
                          padding: const EdgeInsets.all(16),
                        ),
                        child: _loading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                _creatingAccount
                                    ? _tr('Créer le compte', 'Create account')
                                    : _tr('Se connecter', 'Sign in'),
                              ),
                      ),
                      TextButton(
                        onPressed: _loading
                            ? null
                            : () => setState(() {
                                _creatingAccount = !_creatingAccount;
                                _message = null;
                                _error = null;
                              }),
                        child: Text(
                          _creatingAccount
                              ? _tr(
                                  'J’ai déjà un compte',
                                  'I already have an account',
                                )
                              : _tr(
                                  'Créer un nouveau compte',
                                  'Create a new account',
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _chooseSignupMarket() async {
    final market = await showDialog<_MarketOption>(
      context: context,
      builder: (_) => _MarketPickerDialog(
        selectedMarket: _signupMarket,
        languageCode: _activeLanguageCode,
      ),
    );
    if (market != null && mounted) {
      setState(() {
        _signupMarket = market;
        _error = null;
      });
    }
  }
}

class _BusinessAccess {
  const _BusinessAccess({
    required this.id,
    required this.name,
    required this.role,
    this.location = '',
    this.ownerId,
  });

  final String id;
  final String name;
  final String role;
  final String location;
  final String? ownerId;
}

class _CreateBusinessBranchDialog extends StatefulWidget {
  const _CreateBusinessBranchDialog();

  @override
  State<_CreateBusinessBranchDialog> createState() =>
      _CreateBusinessBranchDialogState();
}

class _CreateBusinessBranchDialogState
    extends State<_CreateBusinessBranchDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _location = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _location.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Ajouter une boutique'),
    content: Form(
      key: _formKey,
      child: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Cette boutique aura son propre stock, ses ventes et ses dépenses. '
              'Le nombre de boutiques dépend de votre forfait et les limites de '
              'produits et de reçus sont partagées entre vos boutiques.',
            ),
            const SizedBox(height: 18),
            TextFormField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Nom de la boutique',
                prefixIcon: Icon(Icons.storefront_outlined),
                border: OutlineInputBorder(),
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Indique le nom de la boutique.'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _location,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Zone ou adresse (facultatif)',
                prefixIcon: Icon(Icons.location_on_outlined),
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Annuler'),
      ),
      FilledButton.icon(
        onPressed: () {
          if (!_formKey.currentState!.validate()) return;
          Navigator.pop(context, {
            'name': _name.text.trim(),
            'location': _location.text.trim(),
          });
        },
        icon: const Icon(Icons.add_business_outlined),
        label: const Text('Créer la boutique'),
      ),
    ],
  );
}

class MultiStoreOverviewContent extends StatefulWidget {
  const MultiStoreOverviewContent({
    super.key,
    required this.businesses,
    required this.isCreating,
    required this.onCreate,
    required this.onOpenBusiness,
  });

  final List<_BusinessAccess> businesses;
  final bool isCreating;
  final VoidCallback onCreate;
  final ValueChanged<String> onOpenBusiness;

  @override
  State<MultiStoreOverviewContent> createState() =>
      _MultiStoreOverviewContentState();
}

class _MultiStoreOverviewContentState extends State<MultiStoreOverviewContent> {
  late Future<List<Map<String, dynamic>>> _summary;
  int _selectedMonthOffset = 0;

  @override
  void initState() {
    super.initState();
    _summary = _loadSummary();
  }

  Future<List<Map<String, dynamic>>> _loadSummary() async {
    final monthStart = _monthStart(_selectedMonthOffset);
    final rows = await Supabase.instance.client.rpc(
      'get_owned_business_summaries',
      params: {'p_month_start': _dateOnly(monthStart)},
    );
    return List<Map<String, dynamic>>.from(
      (rows as List).map((row) => Map<String, dynamic>.from(row as Map)),
    );
  }

  DateTime _monthStart(int monthsAgo) {
    final now = DateTime.now();
    return DateTime(now.year, now.month - monthsAgo);
  }

  String _dateOnly(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  String _monthLabel(DateTime month, {bool abbreviated = false}) {
    const fullNames = [
      'janvier',
      'février',
      'mars',
      'avril',
      'mai',
      'juin',
      'juillet',
      'août',
      'septembre',
      'octobre',
      'novembre',
      'décembre',
    ];
    const shortNames = [
      'janv.',
      'févr.',
      'mars',
      'avr.',
      'mai',
      'juin',
      'juil.',
      'août',
      'sept.',
      'oct.',
      'nov.',
      'déc.',
    ];
    final name = (abbreviated ? shortNames : fullNames)[month.month - 1];
    return '$name ${month.year}';
  }

  String _money(num value, String currency) {
    final grouped = value.round().toString().replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ' ',
    );
    return '$grouped $currency';
  }

  num _number(Map<String, dynamic> row, String key) {
    final value = row[key];
    if (value is num) return value;
    return num.tryParse(value?.toString() ?? '') ?? 0;
  }

  @override
  Widget build(
    BuildContext context,
  ) => FutureBuilder<List<Map<String, dynamic>>>(
    future: _summary,
    builder: (context, snapshot) {
      final rows = snapshot.data ?? const <Map<String, dynamic>>[];
      final totalsByCurrency = <String, Map<String, num>>{};
      for (final row in rows) {
        final currency = row['currency_code']?.toString() ?? 'XOF';
        final totals = totalsByCurrency.putIfAbsent(
          currency,
          () => {'revenue': 0, 'net_profit': 0, 'expenses': 0},
        );
        totals['revenue'] = totals['revenue']! + _number(row, 'revenue');
        totals['net_profit'] =
            totals['net_profit']! + _number(row, 'net_profit');
        totals['expenses'] = totals['expenses']! + _number(row, 'expenses');
      }
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Mes boutiques',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Stocks, ventes et résultats suivis séparément pour chaque point de vente.',
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: widget.isCreating ? null : widget.onCreate,
                icon: widget.isCreating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add_business_outlined),
                label: const Text('Ajouter une boutique'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (snapshot.hasError)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(
                      Icons.cloud_off_outlined,
                      color: Colors.deepOrange,
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'La synthèse des boutiques n’est pas disponible. Vérifie que les fonctions multi-boutiques sont installées dans Supabase.',
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () =>
                          setState(() => _summary = _loadSummary()),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Réessayer'),
                    ),
                  ],
                ),
              ),
            )
          else if (snapshot.connectionState == ConnectionState.waiting)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(36),
                child: CircularProgressIndicator(),
              ),
            )
          else ...[
            if (rows.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text(
                    'Aucune boutique propriétaire trouvée pour ce compte.',
                  ),
                ),
              ),
            if (totalsByCurrency.isNotEmpty) ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Synthèse de ${_monthLabel(_monthStart(_selectedMonthOffset))}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  DropdownButton<int>(
                    value: _selectedMonthOffset,
                    onChanged: (value) {
                      if (value == null || value == _selectedMonthOffset)
                        return;
                      setState(() {
                        _selectedMonthOffset = value;
                        _summary = _loadSummary();
                      });
                    },
                    items: List.generate(12, (offset) {
                      final month = _monthStart(offset);
                      return DropdownMenuItem<int>(
                        value: offset,
                        child: Text(_monthLabel(month)),
                      );
                    }),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: totalsByCurrency.entries.map((entry) {
                  final totals = entry.value;
                  return SizedBox(
                    width: 300,
                    child: Card(
                      elevation: 2,
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Total en ${entry.key}',
                              style: const TextStyle(
                                color: teal,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Ventes  ·  ${_money(totals['revenue']!, entry.key)}',
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Bénéfice net estimé  ·  ${_money(totals['net_profit']!, entry.key)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Dépenses  ·  ${_money(totals['expenses']!, entry.key)}',
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Chaque boutique garde son propre stock et ses propres limites.',
                              style: TextStyle(
                                color: Colors.black54,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 22),
            ],
            Text(
              'Résultats par boutique',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            ...rows.map((row) {
              final id = row['business_id']?.toString() ?? '';
              _BusinessAccess? business;
              for (final candidate in widget.businesses) {
                if (candidate.id == id) {
                  business = candidate;
                  break;
                }
              }
              final name =
                  row['name']?.toString() ?? business?.name ?? 'Boutique';
              final location =
                  row['location']?.toString() ?? business?.location ?? '';
              final currency = row['currency_code']?.toString() ?? 'XOF';
              final profit = _number(row, 'net_profit');
              return Card(
                elevation: 2,
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: teal.withValues(alpha: .1),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(
                              Icons.storefront_outlined,
                              color: teal,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                  ),
                                ),
                                Text(
                                  location.isEmpty
                                      ? 'Zone non précisée'
                                      : location,
                                  style: const TextStyle(color: Colors.black54),
                                ),
                              ],
                            ),
                          ),
                          TextButton.icon(
                            onPressed: id.isEmpty
                                ? null
                                : () => widget.onOpenBusiness(id),
                            icon: const Icon(Icons.open_in_new),
                            label: const Text('Ouvrir'),
                          ),
                        ],
                      ),
                      const Divider(height: 26),
                      Wrap(
                        spacing: 28,
                        runSpacing: 16,
                        children: [
                          _StoreMetric(
                            label: 'Ventes de la période',
                            value: _money(_number(row, 'revenue'), currency),
                            icon: Icons.trending_up,
                            color: teal,
                          ),
                          _StoreMetric(
                            label: 'Bénéfice net estimé',
                            value: _money(profit, currency),
                            icon: profit < 0
                                ? Icons.trending_down
                                : Icons.savings_outlined,
                            color: profit < 0 ? Colors.red : teal,
                          ),
                          _StoreMetric(
                            label: 'Dépenses de la période',
                            value: _money(_number(row, 'expenses'), currency),
                            icon: Icons.receipt_long_outlined,
                            color: Colors.deepOrange,
                          ),
                          _StoreMetric(
                            label: 'Produits en stock',
                            value: _number(
                              row,
                              'products_count',
                            ).round().toString(),
                            icon: Icons.inventory_2_outlined,
                            color: navy,
                          ),
                          _StoreMetric(
                            label: 'Crédits clients',
                            value: _money(
                              _number(row, 'customer_credit'),
                              currency,
                            ),
                            icon: Icons.account_balance_wallet_outlined,
                            color: Colors.indigo,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ],
      );
    },
  );
}

class _StoreMetric extends StatelessWidget {
  const _StoreMetric({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 200,
    child: Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(color: Colors.black54, fontSize: 12),
              ),
              Text(
                value,
                style: TextStyle(color: color, fontWeight: FontWeight.w700),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key, required this.userId, required this.email});

  final String userId;
  final String email;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final BrowserOnlineEvents _browserOnlineEvents = BrowserOnlineEvents();
  String get _storageKey =>
      'bizgestion_local_data_${widget.userId}_${_businessId ?? 'unassigned'}_v2';
  String get _pendingSyncKey =>
      'bizgestion_pending_sync_${widget.userId}_${_businessId ?? 'unassigned'}_v1';
  String get _pendingSyncBaseRevisionKey =>
      'bizgestion_pending_sync_revision_${widget.userId}_${_businessId ?? 'unassigned'}_v1';
  String get _businessNameKey =>
      'bizgestion_business_name_${widget.userId}_${_businessId ?? 'unassigned'}_v1';
  String get _businessRoleKey =>
      'bizgestion_business_role_${widget.userId}_${_businessId ?? 'unassigned'}_v1';
  String get _cloudRevisionKey =>
      'bizgestion_cloud_revision_${widget.userId}_${_businessId ?? 'unassigned'}_v1';
  String get _unassignedStorageKey =>
      'bizgestion_local_data_${widget.userId}_unassigned_v2';
  String get _legacyUserStorageKey =>
      'bizgestion_local_data_${widget.userId}_v1';
  String get _selectedBusinessKey =>
      'bizgestion_selected_business_${widget.userId}_v1';
  static const _legacyStorageKey = 'bizgestion_local_data_v1';
  static const _legacyMigrationKey = 'bizgestion_legacy_migration_completed_v1';
  bool _ready = false;
  int selectedIndex = 0;
  String _dashboardPeriod = 'Ce mois';
  String? _businessId;
  String? _businessName;
  String? _businessRole;
  BusinessProfile _businessProfile = const BusinessProfile();
  List<_BusinessAccess> _businessAccess = [];
  bool _creatingBusiness = false;
  int _cloudRevision = 0;
  Map<String, dynamic>? _lastCloudSnapshot;
  int _dataRefreshKey = 0;
  Future<void> _saveQueue = Future<void>.value();
  int _receiptSequence = 0;
  int _paymentSequence = 0;
  String? _syncError;
  String? _syncErrorDetail;
  RealtimeChannel? _businessUpdatesChannel;
  bool _syncConflictNeedsChoice = false;
  Future<void> _localSaveQueue = Future<void>.value();
  final List<Product> products = [];
  final List<PurchaseRecord> purchases = [];
  final List<SupplierRecord> suppliers = [];
  final List<SaleRecord> sales = [];
  final List<PaymentRecord> customerPayments = [];
  final List<RefundRecord> refunds = [];
  final List<ExpenseRecord> expenses = [];
  final List<StocktakeRecord> stocktakes = [];
  final List<CashMovement> cashMovements = [];

  Future<void> _openSubscription() async {
    final id = _businessId;
    if (id == null) return;
    final now = DateTime.now();
    var productsUsed = products.length;
    var receiptsThisMonth = sales
        .where(
          (sale) => sale.date.year == now.year && sale.date.month == now.month,
        )
        .map((sale) => sale.receiptNumber)
        .toSet()
        .length;
    var totalReceipts = sales.map((sale) => sale.receiptNumber).toSet().length;
    try {
      final usage = await Supabase.instance.client.rpc(
        'get_owned_business_usage',
      );
      if (usage is Map) {
        productsUsed =
            (usage['products_used'] as num?)?.toInt() ?? productsUsed;
        receiptsThisMonth =
            (usage['receipts_this_month'] as num?)?.toInt() ??
            receiptsThisMonth;
        totalReceipts =
            (usage['total_receipts'] as num?)?.toInt() ?? totalReceipts;
      }
    } catch (error) {
      debugPrint(
        'Usage multi-boutiques indisponible, affichage local : $error',
      );
    }
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SubscriptionPage(
          businessId: id,
          businessName: _businessName ?? 'Mon commerce',
          canManageSubscription: _businessRole == 'owner',
          currencyCode: _activeCurrencyCode,
          productsUsed: productsUsed,
          salesUsedThisMonth: receiptsThisMonth,
          totalSalesCount: totalReceipts,
        ),
      ),
    );
  }

  void _openStartupGuide() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 680,
            maxHeight: MediaQuery.sizeOf(dialogContext).height * .86,
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(colors: [navy, Color(0xFF168E9B)]),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.menu_book_rounded, color: Colors.white),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _tr(
                          'Guide de démarrage BizGestion',
                          'BizGestion quick start guide',
                        ),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      icon: const Icon(Icons.close, color: Colors.white),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(18),
                  children: [
                    _GuideSection(
                      icon: Icons.storefront_outlined,
                      title: _tr(
                        '1. Configure ton commerce',
                        '1. Set up your business',
                      ),
                      body: _tr(
                        'Renseigne le nom et les coordonnées du commerce, puis ajoute les produits avec leur unité, prix d’achat, prix de vente et seuil d’alerte. Ajoute ensuite les quantités reçues dans Achats : l’approvisionnement met à jour le stock.',
                        'Enter your business name and details, then add products with units, costs, selling prices, and alert thresholds. Record received quantities in Purchases to update stock.',
                      ),
                    ),
                    _GuideSection(
                      icon: Icons.point_of_sale_outlined,
                      title: _tr('2. Enregistre les ventes', '2. Record sales'),
                      body: _tr(
                        'Choisis le produit et la quantité, indique le client si besoin, puis le mode de paiement. Une vente peut être payée, partiellement payée ou à crédit. Le reçu conserve le total, le montant encaissé et le reste dû.',
                        'Choose products and quantities, add customer details if needed, then select payment. A sale can be paid, partially paid, or on credit. The receipt records the total, amount received, and balance due.',
                      ),
                    ),
                    _GuideSection(
                      icon: Icons.assignment_return_outlined,
                      title: _tr(
                        '3. Crédits, retours et remboursements',
                        '3. Credits, returns, and refunds',
                      ),
                      body: _tr(
                        'Depuis le reçu, enregistre les paiements reçus plus tard. Pour un retour, saisis la quantité réellement rendue : elle revient au stock et le remboursement est calculé à partir du montant effectivement payé. Un retour de marchandise et un simple ajustement de prix ne sont pas la même opération.',
                        'From the receipt, record later payments. For a return, enter the actual quantity returned: it goes back into stock, and the refund is based on the amount actually paid. Returning goods and adjusting a price are different operations.',
                      ),
                    ),
                    _GuideSection(
                      icon: Icons.wifi_off_rounded,
                      title: _tr(
                        '4. Travaille hors connexion et synchronise',
                        '4. Work offline and sync',
                      ),
                      body: _tr(
                        'Après une première connexion, les données de travail sont conservées sur cet appareil. Hors ligne, les changements restent locaux et se synchronisent quand la connexion revient. Vérifie l’icône cloud et utilise « Réessayer » si une synchronisation est signalée en attente. Ne supprime pas les données du navigateur avant leur synchronisation.',
                        'After connecting once, your working data is stored on this device. Offline changes remain local and sync when the connection returns. Check the cloud icon and use Retry if sync is pending. Do not clear browser data before syncing.',
                      ),
                    ),
                    _GuideSection(
                      icon: Icons.install_mobile_outlined,
                      title: _tr(
                        '5. Installe BizGestion sur ton téléphone',
                        '5. Install BizGestion on your phone',
                      ),
                      body: _tr(
                        'Android : ouvre le site dans Chrome, touche ⋮ puis « Installer l’application » ou « Ajouter à l’écran d’accueil ». iPhone : ouvre le site dans Safari, touche Partager puis « Sur l’écran d’accueil ». Ouvre ensuite l’icône BizGestion et connecte-toi en ligne une première fois.',
                        'Android: open the site in Chrome, tap ⋮, then Install app or Add to Home screen. iPhone: open it in Safari, tap Share, then Add to Home Screen. Open the BizGestion icon and sign in online once.',
                      ),
                    ),
                    _GuideSection(
                      icon: Icons.workspace_premium_outlined,
                      title: _tr(
                        '6. Abonnements et offre Chariow',
                        '6. Plans and Chariow offer',
                      ),
                      body: _tr(
                        'Découverte est gratuit. Commerce et Entreprise proposent des limites plus élevées, avec paiement mensuel ou annuel. Vérifie le montant et la période dans PayPal avant de confirmer. L’offre Chariow à 2 500 FCFA (« Créer un compte PayPal depuis l’Afrique ») est une offre distincte, pas un forfait BizGestion.',
                        'Découverte is free. Commerce and Entreprise offer higher limits with monthly or yearly billing. Check the amount and billing period in PayPal before confirming. The 2,500 FCFA Chariow offer is separate from BizGestion plans.',
                      ),
                    ),
                    _GuideSection(
                      icon: Icons.cloud_sync_outlined,
                      title: _tr(
                        '7. Sauvegarde et équipe',
                        '7. Backups and team',
                      ),
                      body: _tr(
                        'Le propriétaire ou l’administrateur peut exporter une sauvegarde, restaurer un fichier et gérer les membres selon les droits du forfait. Fais une sauvegarde avant une restauration ou un changement important. Le journal d’activité aide à retrouver les opérations de l’équipe.',
                        'Owners and admins can export a backup, restore a file, and manage team members according to the plan. Back up before restoring or making major changes. The activity log helps review team operations.',
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: FilledButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(_tr('J’ai compris', 'Got it')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSyncErrorDetails() {
    final summary = _syncError == null ? '' : _localizedSyncError(_syncError!);
    final detail = _syncErrorDetail?.trim() ?? '';
    if (summary.isEmpty && detail.isEmpty) return;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_tr('Détail de synchronisation', 'Sync details')),
        content: SizedBox(
          width: _dialogWidth(context, 560),
          child: SingleChildScrollView(
            child: SelectableText(
              [
                if (summary.isNotEmpty) summary,
                if (detail.isNotEmpty && detail != summary) detail,
              ].join('\\n\\n'),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(_tr('Fermer', 'Close')),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmSignOut() async {
    final shouldSignOut = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_tr('Se déconnecter ?', 'Sign out?')),
        content: Text(
          _tr(
            'Veux-tu vraiment te déconnecter de BizGestion ?',
            'Are you sure you want to sign out of BizGestion?',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(_tr('Rester connecté', 'Stay signed in')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(_tr('Se déconnecter', 'Sign out')),
          ),
        ],
      ),
    );
    if (shouldSignOut != true || !mounted) return;
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _tr(
              'La déconnexion a échoué. Réessaie.',
              'Sign out failed. Please try again.',
            ),
          ),
        ),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _browserOnlineEvents.listen(() {
      if (mounted && _syncError != null && !_syncConflictNeedsChoice) {
        _loadData();
      }
    });
    _loadData();
  }

  Future<void> _loadData({String? requestedBusinessId}) async {
    await _stopBusinessUpdates();
    _syncConflictNeedsChoice = false;
    final previousBusinessId = _businessId;
    _businessId = null;
    _businessName = null;
    _businessRole = null;
    _cloudRevision = 0;
    _lastCloudSnapshot = null;
    final preferences = await SharedPreferences.getInstance();
    Map<String, dynamic>? localData;
    final cachedBusinessId =
        requestedBusinessId ?? preferences.getString(_selectedBusinessKey);
    if (cachedBusinessId != previousBusinessId) _restoreSnapshot({});
    if (cachedBusinessId != null) {
      _businessId = cachedBusinessId;
      _businessName = preferences.getString(_businessNameKey);
      _businessRole = preferences.getString(_businessRoleKey);
      _cloudRevision = preferences.getInt(_cloudRevisionKey) ?? 0;
    }
    try {
      final saved = preferences.getString(_storageKey);
      if (saved != null) {
        localData = Map<String, dynamic>.from(jsonDecode(saved));
        _restoreSnapshot(localData);
      }
    } catch (error) {
      debugPrint('Chargement local BizGestion impossible : $error');
    }
    // Show the last business snapshot immediately. The cloud request below may
    // time out when this previously signed-in device is offline.
    if (!_ready && mounted && cachedBusinessId != null) {
      setState(() => _ready = true);
    }
    try {
      final client = Supabase.instance.client;
      final memberships = await client
          .from('business_members')
          .select('business_id, role')
          .eq('user_id', widget.userId)
          .order('created_at');
      if ((memberships as List).isEmpty) {
        _businessAccess = [];
        if (cachedBusinessId != null) {
          _businessId = null;
          _businessName = null;
          _businessRole = null;
          await preferences.remove(_selectedBusinessKey);
          localData = null;
          _restoreSnapshot({});
        }
        throw StateError('Aucun commerce associé à ce compte.');
      }
      final memberRows = List<Map<String, dynamic>>.from(memberships);
      final businessIds = memberRows
          .map((item) => item['business_id'] as String)
          .toList();
      final businessRows = await client
          .from('businesses')
          .select('id, name, location, owner_id')
          .inFilter('id', businessIds);
      final businessDetails = <String, Map<String, dynamic>>{
        for (final item in businessRows)
          item['id'] as String: Map<String, dynamic>.from(item),
      };
      _businessAccess = memberRows.map((item) {
        final id = item['business_id'] as String;
        final details = businessDetails[id] ?? const <String, dynamic>{};
        return _BusinessAccess(
          id: id,
          name: details['name'] as String? ?? 'Mon commerce',
          role: item['role'] as String? ?? 'staff',
          location: details['location'] as String? ?? '',
          ownerId: details['owner_id'] as String?,
        );
      }).toList();
      final preferredBusinessId =
          requestedBusinessId ?? preferences.getString(_selectedBusinessKey);
      final selected = _businessAccess.firstWhere(
        (item) => item.id == preferredBusinessId,
        orElse: () => _businessAccess.first,
      );
      _businessId = selected.id;
      _businessName = selected.name;
      _businessRole = selected.role;
      if (_businessRole == 'staff' &&
          selectedIndex != 1 &&
          selectedIndex != 3 &&
          selectedIndex != 4) {
        selectedIndex = 1;
      }
      await preferences.setString(_selectedBusinessKey, selected.id);
      await preferences.setString(_businessNameKey, selected.name);
      await preferences.setString(_businessRoleKey, selected.role);

      try {
        localData = null;
        var saved = preferences.getString(_storageKey);
        if (saved == null && selected.id == _businessAccess.first.id) {
          saved = preferences.getString(_legacyUserStorageKey);
          if (saved == null &&
              !(preferences.getBool(_legacyMigrationKey) ?? false)) {
            saved = preferences.getString(_legacyStorageKey);
            await preferences.setBool(_legacyMigrationKey, true);
          }
          if (saved == null) {
            saved = preferences.getString(_unassignedStorageKey);
            if (saved != null) {
              final unassignedData = Map<String, dynamic>.from(
                jsonDecode(saved),
              );
              if (_hasSnapshotData(unassignedData)) {
                await preferences.setInt(_pendingSyncBaseRevisionKey, 0);
                await preferences.setBool(_pendingSyncKey, true);
              }
            }
          }
          if (saved != null) await preferences.setString(_storageKey, saved);
        }
        if (saved != null) {
          localData = Map<String, dynamic>.from(jsonDecode(saved));
          _restoreSnapshot(localData);
        } else {
          _restoreSnapshot({});
        }
      } catch (error) {
        debugPrint('Chargement local BizGestion impossible : $error');
      }

      final cloudResult = await client.rpc(
        'load_business_records_snapshot',
        params: {'target_business_id': _businessId!},
      );
      final cloudRow = Map<String, dynamic>.from(cloudResult as Map);
      _cloudRevision = (cloudRow['revision'] as num).toInt();
      await preferences.setInt(_cloudRevisionKey, _cloudRevision);
      final cloudData = Map<String, dynamic>.from(cloudRow['data'] as Map);
      _lastCloudSnapshot = cloudData;
      // Staff can keep local sales and payment changes while offline, but the
      // commerce profile (including its language) is owner-managed. Always
      // refresh that metadata from the cloud before any local snapshot restore.
      final sharedProfile = cloudData['businessProfile'];
      if (_businessRole == 'staff' &&
          localData != null &&
          sharedProfile is Map) {
        localData['businessProfile'] = Map<String, dynamic>.from(sharedProfile);
      }
      final hasPendingLocalChanges =
          preferences.getBool(_pendingSyncKey) ?? false;
      final pendingBaseRevision = preferences.getInt(
        _pendingSyncBaseRevisionKey,
      );
      if (hasPendingLocalChanges && localData != null) {
        if (pendingBaseRevision == _cloudRevision) {
          await _writeCloudSnapshot(localData);
          await preferences.setString(_storageKey, jsonEncode(localData));
          await preferences.remove(_pendingSyncKey);
          await preferences.remove(_pendingSyncBaseRevisionKey);
          _restoreSnapshot(localData);
        } else {
          // Keep the unsynchronized local copy intact. The user can choose
          // which version to keep after reviewing the conflict prompt.
          _restoreSnapshot(localData);
          _syncConflictNeedsChoice = true;
          _syncError = 'La copie cloud a changé pendant que cet appareil était hors ligne. Choisis quelle version conserver.';
        }
      } else if (_hasSnapshotData(localData) && !_hasSnapshotData(cloudData)) {
        await _writeCloudSnapshot(localData!);
        _restoreSnapshot(localData);
      } else {
        _restoreSnapshot(cloudData);
        await preferences.setString(_storageKey, jsonEncode(cloudData));
      }
      if (!_syncConflictNeedsChoice) {
        _syncError = null;
        _syncErrorDetail = null;
      }
    } catch (error) {
      debugPrint('Chargement cloud BizGestion impossible : $error');
      _syncErrorDetail = error.toString();
      _syncError =
          error is StateError &&
              error.message.toString() == 'Aucun commerce associé à ce compte.'
          ? 'Aucun commerce cloud n’est associé à ce compte. Les données restent enregistrées sur cet appareil.'
          : cachedBusinessId != null && _hasSnapshotData(localData)
          ? 'Connexion cloud indisponible. Les données enregistrées sur cet appareil restent accessibles; réessaie quand Internet revient.'
          : 'Le cloud BizGestion n’est pas encore prêt. Vérifie le script SQL Supabase; en attendant, les données restent sur cet appareil.';
    }
    if (mounted) setState(() => _ready = true);
    _watchBusinessUpdates();
  }

  Future<void> _resolvePendingSyncConflict() async {
    final keepLocal = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Deux versions des données'),
        content: const Text(
          'Cet appareil a des changements enregistrés hors ligne et le cloud a aussi été modifié. Choisis la version à conserver. Envoyer la copie de cet appareil remplacera la version cloud actuelle.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Garder la copie cloud'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Envoyer ma copie locale'),
          ),
        ],
      ),
    );
    if (keepLocal == null || !mounted) return;
    final preferences = await SharedPreferences.getInstance();
    try {
      if (keepLocal) {
        final snapshot = _makeSnapshot();
        await _writeCloudSnapshot(snapshot);
        await preferences.setString(_storageKey, jsonEncode(snapshot));
      } else {
        final cloudRow = Map<String, dynamic>.from(
          await Supabase.instance.client.rpc(
            'load_business_records_snapshot',
            params: {'target_business_id': _businessId!},
          ) as Map,
        );
        _cloudRevision = (cloudRow['revision'] as num).toInt();
        await preferences.setInt(_cloudRevisionKey, _cloudRevision);
        final cloudData = Map<String, dynamic>.from(cloudRow['data'] as Map);
        _restoreSnapshot(cloudData);
        await preferences.setString(_storageKey, jsonEncode(cloudData));
      }
      await preferences.remove(_pendingSyncKey);
      await preferences.remove(_pendingSyncBaseRevisionKey);
      if (mounted) {
        setState(() {
          _syncError = null;
          _syncConflictNeedsChoice = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              keepLocal
                  ? 'La copie locale a remplacé la version cloud.'
                  : 'La copie cloud a été rechargée sur cet appareil.',
            ),
          ),
        );
      }
    } catch (error) {
      debugPrint('Résolution du conflit cloud BizGestion impossible : $error');
      final businessId = _businessId;
      if (businessId != null &&
          error.toString().contains('Conflit de synchronisation')) {
        await _loadData(requestedBusinessId: businessId);
        return;
      }
      if (mounted)
        setState(
          () => _syncError = 'Impossible de résoudre le conflit. Les deux copies sont conservées; réessaie quand la connexion sera stable.',
        );
    }
  }

  Future<void> _chooseBusiness(String businessId) async {
    if (businessId == _businessId) return;
    await _loadData(requestedBusinessId: businessId);
  }

  List<_BusinessAccess> get _ownedBusinesses => _businessAccess
      .where(
        (business) =>
            business.role == 'owner' && business.ownerId == widget.userId,
      )
      .toList();

  Future<void> _createBusinessBranch() async {
    if (_creatingBusiness) return;
    final details = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => const _CreateBusinessBranchDialog(),
    );
    if (details == null || !mounted) return;
    setState(() => _creatingBusiness = true);
    try {
      dynamic result;
      try {
        result = await Supabase.instance.client.rpc(
          'create_business_branch',
          params: {
            'branch_name': details['name'],
            'branch_location': details['location'],
          },
        );
      } catch (error) {
        debugPrint('RPC create_business_branch a échoué : $error');
        if (mounted) {
          final detail = error.toString().replaceAll('\n', ' ').trim();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Création impossible : $detail'),
              duration: const Duration(seconds: 12),
            ),
          );
        }
        return;
      }
      final newBusinessId = result.toString();
      try {
        await _loadData(requestedBusinessId: _businessId);
      } catch (error) {
        debugPrint('Boutique créée mais actualisation échouée : $error');
        if (mounted) {
          final detail = error.toString().replaceAll('\n', ' ').trim();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Boutique créée, actualisation impossible : $detail',
              ),
              duration: const Duration(seconds: 12),
            ),
          );
        }
        return;
      }
      if (!mounted) return;
      setState(() => selectedIndex = 8);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Boutique « ${details['name']} » créée.')),
      );
      debugPrint('Nouvelle boutique BizGestion créée : $newBusinessId');
    } finally {
      if (mounted) setState(() => _creatingBusiness = false);
    }
  }

  Future<void> _stopBusinessUpdates() async {
    final channel = _businessUpdatesChannel;
    _businessUpdatesChannel = null;
    if (channel != null) {
      await Supabase.instance.client.removeChannel(channel);
    }
  }

  void _watchBusinessUpdates() {
    final businessId = _businessId;
    if (businessId == null) return;
    _businessUpdatesChannel = Supabase.instance.client
        .channel('business-data-updates:$businessId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'business_data_updates',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'business_id',
            value: businessId,
          ),
          callback: (payload) {
            final update = payload.newRecord;
            final revision = (update['revision'] as num?)?.toInt() ?? 0;
            if (revision <= _cloudRevision) return;
            // Laisse à l'enregistrement local le temps de recevoir sa nouvelle
            // révision, puis recharge les réglages partagés et les données.
            Future<void>.delayed(const Duration(seconds: 1), () {
              if (!mounted || revision <= _cloudRevision) return;
              _loadData();
            });
          },
        )
        .subscribe();
  }

  void _restoreSnapshot(Map<String, dynamic>? data) {
    if (data == null) return;
    _businessProfile = BusinessProfile.fromJson(
      data['businessProfile'] is Map
          ? Map<String, dynamic>.from(data['businessProfile'] as Map)
          : const {},
    );
    _activeCountryCode = _businessProfile.countryCode;
    _activeCurrencyCode = _businessProfile.currencyCode;
    _setActiveLanguage(_businessProfile.languageCode);
    products
      ..clear()
      ..addAll(
        (data['products'] as List? ?? []).map(
          (e) => Product.fromJson(Map<String, dynamic>.from(e)),
        ),
      );
    purchases
      ..clear()
      ..addAll(
        (data['purchases'] as List? ?? []).map(
          (e) => PurchaseRecord.fromJson(Map<String, dynamic>.from(e)),
        ),
      );
    suppliers
      ..clear()
      ..addAll(
        (data['suppliers'] as List? ?? []).map(
          (e) => SupplierRecord.fromJson(Map<String, dynamic>.from(e)),
        ),
      );
    sales
      ..clear()
      ..addAll(
        (data['sales'] as List? ?? []).map(
          (e) => SaleRecord.fromJson(Map<String, dynamic>.from(e)),
        ),
      );
    final savedReceiptSequence =
        (data['receiptSequence'] as num?)?.toInt() ?? 0;
    _receiptSequence = savedReceiptSequence;
    for (final sale in sales) {
      final match = RegExp(r'^V-(\d+)$').firstMatch(sale.receiptNumber);
      final sequence = int.tryParse(match?.group(1) ?? '') ?? 0;
      if (sequence > _receiptSequence) _receiptSequence = sequence;
    }
    customerPayments
      ..clear()
      ..addAll(
        (data['payments'] as List? ?? []).map(
          (e) => PaymentRecord.fromJson(Map<String, dynamic>.from(e)),
        ),
      );
    _paymentSequence = (data['paymentSequence'] as num?)?.toInt() ?? 0;
    for (final payment in customerPayments) {
      final match = RegExp(r'^P-(\d+)$').firstMatch(payment.receiptNumber);
      final sequence = int.tryParse(match?.group(1) ?? '') ?? 0;
      if (sequence > _paymentSequence) _paymentSequence = sequence;
    }
    refunds
      ..clear()
      ..addAll(
        (data['refunds'] as List? ?? []).map(
          (e) => RefundRecord.fromJson(Map<String, dynamic>.from(e)),
        ),
      );
    expenses
      ..clear()
      ..addAll(
        (data['expenses'] as List? ?? []).map(
          (e) => ExpenseRecord.fromJson(Map<String, dynamic>.from(e)),
        ),
      );
    stocktakes
      ..clear()
      ..addAll(
        (data['stocktakes'] as List? ?? []).map(
          (e) => StocktakeRecord.fromJson(Map<String, dynamic>.from(e)),
        ),
      );
    cashMovements
      ..clear()
      ..addAll(
        (data['cashMovements'] as List? ?? []).map(
          (e) => CashMovement.fromJson(Map<String, dynamic>.from(e)),
        ),
      );
  }

  bool _hasSnapshotData(Map<String, dynamic>? data) {
    if (data == null) return false;
    final hasRecords = [
      'products',
      'purchases',
      'suppliers',
      'sales',
      'payments',
      'refunds',
      'expenses',
      'stocktakes',
      'cashMovements',
    ].any((key) => (data[key] as List? ?? []).isNotEmpty);
    if (hasRecords) return true;
    final profile = data['businessProfile'] as Map?;
    if (profile == null) return false;
    return profile.entries.any((entry) {
      final value = entry.value?.toString().trim() ?? '';
      return value.isNotEmpty &&
          !(entry.key == 'receiptFooter' &&
              value == 'Merci pour votre confiance !');
    });
  }

  Map<String, dynamic> _makeSnapshot() => {
    'receiptSequence': _receiptSequence,
    'paymentSequence': _paymentSequence,
    'products': products.map((e) => e.toJson()).toList(),
    'businessProfile': _businessProfile.toJson(),
    'purchases': purchases.map((e) => e.toJson()).toList(),
    'suppliers': suppliers.map((e) => e.toJson()).toList(),
    'sales': sales.map((e) => e.toJson()).toList(),
    'payments': customerPayments.map((e) => e.toJson()).toList(),
    'refunds': refunds.map((e) => e.toJson()).toList(),
    'expenses': expenses.map((e) => e.toJson()).toList(),
    'stocktakes': stocktakes.map((e) => e.toJson()).toList(),
    'cashMovements': cashMovements.map((e) => e.toJson()).toList(),
  };

  Future<Map<String, dynamic>> _loadSalesPage(int offset, int pageSize) async {
    final businessId = _businessId;
    if (businessId == null) throw StateError('Aucun commerce cloud associé.');
    final result = await Supabase.instance.client.rpc(
      'load_business_sales_page',
      params: {
        'target_business_id': businessId,
        'page_size': pageSize,
        'page_offset': offset,
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<void> _writeCloudSnapshot(Map<String, dynamic> snapshot) async {
    if (_businessId == null) throw StateError('Aucun commerce cloud associé.');
    final savedRevision = await Supabase.instance.client.rpc(
      'save_business_records_snapshot',
      params: {
        'target_business_id': _businessId!,
        'new_data': snapshot,
        'expected_revision': _cloudRevision,
      },
    );
    _cloudRevision = (savedRevision as num).toInt();
    _lastCloudSnapshot = Map<String, dynamic>.from(
      jsonDecode(jsonEncode(snapshot)) as Map,
    );
    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(_cloudRevisionKey, _cloudRevision);
  }

  static const _recordCollections = [
    'products',
    'suppliers',
    'purchases',
    'sales',
    'payments',
    'refunds',
    'expenses',
    'stocktakes',
    'cashMovements',
  ];

  bool _snapshotHasStableRecordIds(Map<String, dynamic> snapshot) {
    for (final collection in _recordCollections) {
      final records = snapshot[collection];
      if (records is! List) return false;
      for (final record in records) {
        if (record is! Map ||
            (record['recordId']?.toString().trim().isEmpty ?? true)) {
          return false;
        }
      }
    }
    return true;
  }

  Map<String, dynamic> _buildCloudDelta(
    Map<String, dynamic> previous,
    Map<String, dynamic> current,
  ) {
    final changed = <String, dynamic>{};
    final deleted = <String, dynamic>{};
    for (final collection in _recordCollections) {
      final previousRows = previous[collection] as List? ?? const [];
      final currentRows = current[collection] as List? ?? const [];
      final previousById = <String, Map<String, dynamic>>{};
      for (final row in previousRows) {
        final record = Map<String, dynamic>.from(row as Map);
        previousById[record['recordId'].toString()] = record;
      }
      final currentIds = <String>{};
      final upserts = <Map<String, dynamic>>[];
      for (final row in currentRows) {
        final record = Map<String, dynamic>.from(row as Map);
        final id = record['recordId'].toString();
        currentIds.add(id);
        final oldRecord = previousById[id];
        if (oldRecord == null || jsonEncode(oldRecord) != jsonEncode(record)) {
          upserts.add(record);
        }
      }
      final removals = previousById.keys
          .where((id) => !currentIds.contains(id))
          .toList(growable: false);
      if (upserts.isNotEmpty) changed[collection] = upserts;
      if (removals.isNotEmpty) deleted[collection] = removals;
    }
    final metadata = Map<String, dynamic>.from(current)
      ..removeWhere((key, _) => _recordCollections.contains(key));
    return {
      'record_changes': changed,
      'deleted_records': deleted,
      'metadata_changes': metadata,
    };
  }

  Future<void> _writeCloudDelta(Map<String, dynamic> snapshot) async {
    final businessId = _businessId;
    final previous = _lastCloudSnapshot;
    if (businessId == null || previous == null) {
      throw StateError('La base de synchronisation BizGestion est absente.');
    }
    final delta = _buildCloudDelta(previous, snapshot);
    final savedRevision = await Supabase.instance.client.rpc(
      'save_business_records_delta',
      params: {
        'target_business_id': businessId,
        ...delta,
        'expected_revision': _cloudRevision,
      },
    );
    _cloudRevision = (savedRevision as num).toInt();
    _lastCloudSnapshot = Map<String, dynamic>.from(
      jsonDecode(jsonEncode(snapshot)) as Map,
    );
    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(_cloudRevisionKey, _cloudRevision);
  }

  Future<bool> _saveData() {
    // Snapshot writes share one revision counter. Queue them so rapid edits
    // cannot race with each other using the same expected cloud revision.
    final snapshot = _makeSnapshot();
    // Persist each edit locally before waiting for the network. This keeps a
    // refresh or a temporarily unavailable cloud from discarding a stock edit.
    final localSave = _localSaveQueue.then(
      (_) => _cacheSnapshotLocally(snapshot),
    );
    _localSaveQueue = localSave.then<void>((_) {}, onError: (Object _) {});
    final result = _saveQueue.then((_) async {
      await localSave;
      return _saveSnapshot(snapshot);
    });
    _saveQueue = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<void> _cacheSnapshotLocally(Map<String, dynamic> snapshot) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_storageKey, jsonEncode(snapshot));
    if (_businessId == null) return;
    if (!(preferences.getBool(_pendingSyncKey) ?? false)) {
      await preferences.setInt(_pendingSyncBaseRevisionKey, _cloudRevision);
    }
    await preferences.setBool(_pendingSyncKey, true);
  }

  Future<bool> _saveSnapshot(Map<String, dynamic> snapshot) async {
    final preferences = await SharedPreferences.getInstance();
    final pendingBaseRevision =
        preferences.getInt(_pendingSyncBaseRevisionKey) ?? _cloudRevision;
    if (_syncConflictNeedsChoice) {
      return false;
    }
    try {
      final lastCloud = _lastCloudSnapshot;
      if (_businessRole != 'staff' &&
          lastCloud != null &&
          _snapshotHasStableRecordIds(lastCloud) &&
          _snapshotHasStableRecordIds(snapshot)) {
        await _writeCloudDelta(snapshot);
      } else {
        await _writeCloudSnapshot(snapshot);
      }
      if (preferences.getString(_storageKey) == jsonEncode(snapshot)) {
        await preferences.remove(_pendingSyncKey);
        await preferences.remove(_pendingSyncBaseRevisionKey);
      } else {
        // A newer local edit was queued while this snapshot was syncing.
        // Keep it marked pending against the revision just saved.
        await preferences.setInt(_pendingSyncBaseRevisionKey, _cloudRevision);
        await preferences.setBool(_pendingSyncKey, true);
      }
      if (mounted) {
        setState(() {
          _dataRefreshKey++;
          _syncError = null;
          _syncErrorDetail = null;
        });
      }
      return true;
    } catch (error) {
      if (_businessId != null) {
        await preferences.setInt(
          _pendingSyncBaseRevisionKey,
          pendingBaseRevision,
        );
        await preferences.setBool(_pendingSyncKey, true);
      }
      debugPrint('Synchronisation cloud BizGestion impossible : $error');
      if (mounted) {
        setState(() {
          _syncErrorDetail = error.toString();
          _syncError =
              error is StateError &&
                  error.message.toString().startsWith('Une autre session')
              ? 'Conflit de synchronisation : recharge l’application pour récupérer la version cloud avant de continuer.'
              : 'Enregistrement cloud impossible. Ta dernière modification est gardée sur cet appareil; vérifie la connexion et les tables Supabase.';
        });
      }
      return false;
    }
  }

  final pages = const [
    'Accueil',
    'Ventes',
    'Achats',
    'Stock',
    'Clients',
    'Dépenses',
    'Rapports',
    'Caisse',
  ];

  Future<void> _addCashMovement() async {
    final movement = await showDialog<CashMovement>(
      context: context,
      builder: (_) => const AddCashMovementDialog(),
    );
    if (movement == null) return;
    setState(() => cashMovements.insert(0, movement));
    await _saveData();
  }

  Future<void> _removeCashMovement(CashMovement movement) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Supprimer ce mouvement ?'),
        content: const Text(
          'Le solde de caisse sera recalculé sans ce mouvement.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Garder'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => cashMovements.remove(movement));
    await _saveData();
  }

  Future<void> _openTeamManagement() async {
    final businessId = _businessId;
    final managerRole = _businessRole;
    if (businessId == null || managerRole == null) return;
    await showDialog<void>(
      context: context,
      builder: (_) => TeamManagementDialog(
        businessId: businessId,
        managerRole: managerRole,
        languageCode: _businessProfile.languageCode,
      ),
    );
  }

  Future<void> _openActivityLog() async {
    final businessId = _businessId;
    if (businessId == null) return;
    await showDialog<void>(
      context: context,
      builder: (_) => BusinessActivityDialog(businessId: businessId),
    );
  }

  Future<void> _addProduct() async {
    final businessId = _businessId;
    if (businessId == null) return;
    final product = await showDialog<Product>(
      context: context,
      builder: (_) => AddProductDialog(
        businessId: businessId,
        existingUnits: products
            .expand((product) => [product.unit, product.retailUnit])
            .toSet(),
        existingBarcodes: products
            .map((product) => product.barcode.toLowerCase())
            .where((code) => code.isNotEmpty)
            .toSet(),
      ),
    );
    if (product != null) {
      setState(() => products.insert(0, product));
      await _saveData();
    }
  }

  Future<void> _recordPurchase(List<PurchaseRecord> batch) async {
    final missingProducts = batch
        .where(
          (purchase) => !products.any(
            (product) => product.recordId == purchase.product.recordId,
          ),
        )
        .map((purchase) => purchase.product.name)
        .toSet();
    if (missingProducts.isNotEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Approvisionnement annulé : produit introuvable dans le stock (${missingProducts.join(', ')}).',
            ),
          ),
        );
      }
      return;
    }

    setState(() {
      for (final purchase in batch) {
        final supplierName = purchase.supplier.trim();
        if (supplierName.isNotEmpty &&
            !suppliers.any(
              (item) => item.name.toLowerCase() == supplierName.toLowerCase(),
            )) {
          suppliers.insert(0, SupplierRecord(name: supplierName));
        }
        final index = products.indexWhere(
          (product) => product.recordId == purchase.product.recordId,
        );
        final product = products[index];
        final newQuantity = product.quantity + purchase.quantity;
        final totalOldCost = product.quantity * product.purchasePrice;
        final totalNewCost =
            purchase.quantity * purchase.unitPrice + purchase.tripExpenses;
        products[index] = product.copyWith(
          quantity: newQuantity,
          purchasePrice: (totalOldCost + totalNewCost) / newQuantity,
        );
        purchases.insert(0, purchase);
      }
    });
    final synced = await _saveData();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          synced
              ? 'Approvisionnement enregistré et synchronisé avec le cloud.'
              : 'Approvisionnement conservé sur cet appareil; synchronisation cloud en attente.',
        ),
      ),
    );
  }

  Future<void> _addExpense() async {
    final expense = await showDialog<ExpenseRecord>(
      context: context,
      builder: (_) => const AddExpenseDialog(),
    );
    if (expense == null) return;
    setState(() => expenses.insert(0, expense));
    await _saveData();
  }

  Future<void> _takeStock() async {
    final adjustments = await showDialog<List<StocktakeRecord>>(
      context: context,
      builder: (_) => StocktakeDialog(products: List<Product>.from(products)),
    );
    if (adjustments == null || adjustments.isEmpty) return;
    setState(() {
      for (final adjustment in adjustments) {
        final index = products.indexOf(adjustment.product);
        if (index >= 0)
          products[index] = adjustment.product.copyWith(
            quantity: adjustment.countedQuantity,
          );
        stocktakes.insert(0, adjustment);
      }
    });
    await _saveData();
  }

  Future<void> _recordStockLoss() async {
    final record = await showDialog<StocktakeRecord>(
      context: context,
      builder: (_) => StockLossDialog(products: List<Product>.from(products)),
    );
    if (record == null) return;
    final index = products.indexWhere(
      (product) => product.recordId == record.product.recordId,
    );
    if (index < 0) return;
    setState(() {
      products[index] = products[index].copyWith(
        quantity: record.countedQuantity,
      );
      stocktakes.insert(0, record);
    });
    final synced = await _saveData();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          synced ? 'Perte enregistrée et synchronisée.' : 'Perte enregistrée sur cet appareil; synchronisation en attente.',
        ),
      ),
    );
  }

  Future<void> _editProduct(Product current) async {
    final businessId = _businessId;
    if (businessId == null) return;
    final updated = await showDialog<Product>(
      context: context,
      builder: (_) => EditProductDialog(
        product: current,
        businessId: businessId,
        existingNames: products
            .where(
              (product) =>
                  !identical(product, current) &&
                  product.category == current.category,
            )
            .map((product) => product.name.trim().toLowerCase())
            .toSet(),
        existingBarcodes: products
            .where((product) => !identical(product, current))
            .map((product) => product.barcode.toLowerCase())
            .where((code) => code.isNotEmpty)
            .toSet(),
      ),
    );
    if (updated == null) return;
    final index = products.indexOf(current);
    if (index < 0) return;
    final conversionChanged =
        (updated.retailUnitsPerStockUnit - current.retailUnitsPerStockUnit)
            .abs() >
        0.000001;
    final retailUnitChanged = updated.retailUnit != current.retailUnit;
    final nameChanged = updated.name != current.name;
    // Reinterpret past quantities only when correcting a conversion in the same
    // retail unit. A change from bidon to litre applies to future sales only.
    final shouldRecalculatePastSales = conversionChanged && !retailUnitChanged;
    var restoredStock = 0.0;
    setState(() {
      if (shouldRecalculatePastSales) {
        for (var saleIndex = 0; saleIndex < sales.length; saleIndex++) {
          final sale = sales[saleIndex];
          if (sale.product.name != current.name ||
              sale.product.category != current.category)
            continue;
          final correctedStockQuantity =
              sale.saleUnit == current.retailUnit &&
                  current.retailUnit != current.unit
              ? sale.quantity / updated.retailUnitsPerStockUnit
              : sale.quantity;
          restoredStock += sale.stockQuantity - correctedStockQuantity;
          sales[saleIndex] = sale.copyWith(
            product: sale.product.copyWith(
              retailUnitsPerStockUnit: updated.retailUnitsPerStockUnit,
            ),
            stockQuantity: correctedStockQuantity,
          );
        }
      }
      if (nameChanged) {
        for (var saleIndex = 0; saleIndex < sales.length; saleIndex++) {
          final sale = sales[saleIndex];
          if (sale.product.name != current.name ||
              sale.product.category != current.category) {
            continue;
          }
          sales[saleIndex] = sale.copyWith(
            product: sale.product.copyWith(name: updated.name),
          );
        }
      }
      products[index] = updated.copyWith(
        quantity: updated.quantity + restoredStock,
      );
    });
    await _saveData();
    if (shouldRecalculatePastSales && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Conversion enregistrée : les ventes concernées et le stock ont été recalculés.',
          ),
        ),
      );
    } else if (retailUnitChanged && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Unité de vente modifiée. Les anciennes ventes gardent leur unité d’origine.',
          ),
        ),
      );
    }
  }

  void _recordSale(List<SaleRecord> batch) {
    for (final sale in batch) {
      final match = RegExp(r'^V-(\d+)$').firstMatch(sale.receiptNumber);
      final sequence = int.tryParse(match?.group(1) ?? '') ?? 0;
      if (sequence > _receiptSequence) _receiptSequence = sequence;
    }
    setState(() {
      for (final sale in batch) {
        final index = _productIndex(sale.product);
        if (index >= 0) {
          products[index] = products[index].copyWith(
            quantity: products[index].quantity - sale.stockQuantity,
          );
        }
        sales.insert(0, sale);
      }
    });
    _saveData();
  }

  int _productIndex(Product product) => products.indexWhere(
    (item) => item.name == product.name && item.category == product.category,
  );

  Future<void> _editSale(SaleRecord sale) async {
    if (sales.any(
          (item) =>
              item.receiptNumber == sale.receiptNumber && item.received > 0,
        ) ||
        sale.quantity <= 0 ||
        refunds.any((item) => item.receiptNumber == sale.receiptNumber))
      return;
    if (_productIndex(sale.product) < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Ce produit a été retiré du stock. Réajoute-le avant de modifier cette vente.',
          ),
        ),
      );
      return;
    }
    final updated = await showDialog<SaleRecord>(
      context: context,
      builder: (_) =>
          EditSaleDialog(sale: sale, products: List<Product>.from(products)),
    );
    if (updated == null) return;
    setState(() {
      final oldKey = sale.product.name + '|' + sale.product.category;
      final newKey = updated.product.name + '|' + updated.product.category;
      final stockChanges = <String, double>{};
      stockChanges.update(
        oldKey,
        (change) => change + sale.stockQuantity,
        ifAbsent: () => sale.stockQuantity,
      );
      stockChanges.update(
        newKey,
        (change) => change - updated.stockQuantity,
        ifAbsent: () => -updated.stockQuantity,
      );
      for (var index = 0; index < products.length; index++) {
        final product = products[index];
        final key = product.name + '|' + product.category;
        final change = stockChanges.remove(key);
        if (change != null)
          products[index] = product.copyWith(
            quantity: product.quantity + change,
          );
      }
      if (stockChanges.containsKey(oldKey) && stockChanges[oldKey]! > 0) {
        products.add(sale.product.copyWith(quantity: stockChanges[oldKey]!));
      }
      final saleIndex = sales.indexOf(sale);
      if (saleIndex >= 0) sales[saleIndex] = updated;
    });
    await _saveData();
  }

  Future<void> _cancelSaleReceipt(SaleRecord sale) async {
    final receiptSales = sales
        .where((item) => item.receiptNumber == sale.receiptNumber)
        .toList();
    if (receiptSales.any((item) => item.received > 0) ||
        refunds.any((item) => item.receiptNumber == sale.receiptNumber))
      return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Annuler cette vente ?'),
        content: Text(
          'Le reçu ${sale.receiptNumber} et ses ${receiptSales.length} article(s) seront retirés. Les quantités seront remises en stock.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Garder la vente'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Annuler le reçu'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() {
      for (final line in receiptSales) {
        final index = _productIndex(line.product);
        if (index >= 0) {
          products[index] = products[index].copyWith(
            quantity: products[index].quantity + line.stockQuantity,
          );
        } else {
          products.add(line.product.copyWith(quantity: line.stockQuantity));
        }
        sales.remove(line);
      }
    });
    await _saveData();
  }

  Future<void> _refundSale(SaleRecord sale) async {
    if (sale.quantity <= 0) return;
    final receiptSales = sales
        .where((item) => item.receiptNumber == sale.receiptNumber)
        .toList();
    final request = await showDialog<RefundRequest>(
      context: context,
      builder: (_) => RefundDialog(sale: sale, receiptSales: receiptSales),
    );
    if (request == null) return;
    final returnedStock = sale.stockQuantity * request.quantity / sale.quantity;
    final returnedValue = sale.unitPrice * request.quantity;
    final receiptTotal = receiptSales.fold(
      0.0,
      (sum, item) => sum + item.total,
    );
    final receiptReceived = receiptSales.fold(
      0.0,
      (sum, item) => sum + item.received,
    );
    final updatedReceiptTotal = (receiptTotal - returnedValue)
        .clamp(0.0, double.infinity)
        .toDouble();
    final cashRefund = (receiptReceived - updatedReceiptTotal)
        .clamp(0.0, double.infinity)
        .toDouble();
    var remainingReceived = receiptReceived - cashRefund;
    final updatedReceiptSales = <SaleRecord>[];
    for (final line in receiptSales) {
      // Sales shown in the paginated list are deserialized separately from
      // the full in-memory snapshot, so object identity is not reliable here.
      final isReturnedLine = line.recordId == sale.recordId;
      final lineTotal = isReturnedLine
          ? (line.total - returnedValue).clamp(0.0, double.infinity).toDouble()
          : line.total;
      final lineReceived = remainingReceived.clamp(0.0, lineTotal).toDouble();
      remainingReceived -= lineReceived;
      updatedReceiptSales.add(
        SaleRecord(
          recordId: line.recordId,
          receiptNumber: line.receiptNumber,
          product: line.product,
          customerName: line.customerName,
          customerPhone: line.customerPhone,
          quantity: isReturnedLine
              ? line.quantity - request.quantity
              : line.quantity,
          saleUnit: line.saleUnit,
          stockQuantity: isReturnedLine
              ? line.stockQuantity - returnedStock
              : line.stockQuantity,
          unitPrice: line.unitPrice,
          total: lineTotal,
          received: lineReceived,
          balance: (lineTotal - lineReceived)
              .clamp(0.0, double.infinity)
              .toDouble(),
          paymentMethod: line.paymentMethod,
          date: line.date,
          dueDate: lineTotal > lineReceived ? line.dueDate : null,
          pickupStatus: line.pickupStatus,
          collectedAt: line.collectedAt,
          initialReceived: line.initialReceived,
        ),
      );
    }
    final record = RefundRecord(
      receiptNumber: sale.receiptNumber,
      customerName: sale.customerName,
      productName: sale.product.name,
      quantity: request.quantity,
      saleUnit: sale.saleUnit,
      value: returnedValue,
      cashRefund: cashRefund,
      paymentMethod: cashRefund > 0
          ? request.paymentMethod
          : 'Réduction du solde dû',
      date: DateTime.now(),
    );
    setState(() {
      for (var index = 0; index < receiptSales.length; index++) {
        final saleIndex = sales.indexOf(receiptSales[index]);
        if (saleIndex >= 0) sales[saleIndex] = updatedReceiptSales[index];
      }
      final productIndex = _productIndex(sale.product);
      if (productIndex >= 0) {
        products[productIndex] = products[productIndex].copyWith(
          quantity: products[productIndex].quantity + returnedStock,
        );
      } else {
        products.add(sale.product.copyWith(quantity: returnedStock));
      }
      refunds.insert(0, record);
    });
    await _saveData();
  }

  Future<void> _markReceiptCollected(SaleRecord sale) async {
    final receiptSales = sales
        .where((item) => item.receiptNumber == sale.receiptNumber)
        .toList();
    if (!receiptSales.any((item) => item.pickupStatus == 'À retirer')) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirmer le retrait du colis ?'),
        content: Text(
          '${sale.customerName} récupère la commande ${sale.receiptNumber}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Pas encore'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Confirmer le retrait'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final collectedAt = DateTime.now();
    setState(() {
      for (final line in receiptSales) {
        final index = sales.indexOf(line);
        if (index < 0) continue;
        sales[index] = SaleRecord(
          receiptNumber: line.receiptNumber,
          product: line.product,
          customerName: line.customerName,
          customerPhone: line.customerPhone,
          quantity: line.quantity,
          saleUnit: line.saleUnit,
          stockQuantity: line.stockQuantity,
          unitPrice: line.unitPrice,
          total: line.total,
          received: line.received,
          balance: line.balance,
          paymentMethod: line.paymentMethod,
          date: line.date,
          dueDate: line.dueDate,
          pickupStatus: 'Retiré',
          collectedAt: collectedAt,
          initialReceived: line.initialReceived,
        );
      }
    });
    await _saveData();
  }

  Future<void> _addSale() async {
    if (products.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ajoute d’abord un produit au stock.')),
      );
      setState(() => selectedIndex = 3);
      return;
    }
    if (products.every((product) => product.quantity <= 0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tous les produits sont en rupture de stock.'),
        ),
      );
      setState(() => selectedIndex = 3);
      return;
    }
    final batch = await showDialog<List<SaleRecord>>(
      context: context,
      builder: (_) => AddSaleDialog(
        products: products,
        receiptNumber: 'V-' + (_receiptSequence + 1).toString().padLeft(4, '0'),
      ),
    );
    if (batch != null && batch.isNotEmpty) _recordSale(batch);
  }

  Future<void> _collectCustomerPayment(
    String customerName,
    double balance,
  ) async {
    final payment = await showDialog<PaymentRecord>(
      context: context,
      builder: (_) => AddPaymentDialog(
        customerName: customerName,
        balance: balance,
        receiptNumber: 'P-' + (_paymentSequence + 1).toString().padLeft(4, '0'),
      ),
    );
    if (payment == null) return;
    final match = RegExp(r'^P-(\d+)$').firstMatch(payment.receiptNumber);
    final sequence = int.tryParse(match?.group(1) ?? '') ?? 0;
    if (sequence > _paymentSequence) _paymentSequence = sequence;

    setState(() {
      var remaining = payment.amount;
      final oldestFirst =
          sales
              .where(
                (sale) => sale.customerName == customerName && sale.balance > 0,
              )
              .toList()
            ..sort((a, b) => a.date.compareTo(b.date));
      for (final sale in oldestFirst) {
        if (remaining <= 0) break;
        final amountForSale = remaining < sale.balance
            ? remaining
            : sale.balance;
        final index = sales.indexOf(sale);
        sales[index] = sale.withPayment(amountForSale);
        remaining -= amountForSale;
      }
      customerPayments.insert(0, payment);
    });
    await _saveData();
  }

  Future<void> _editBusinessProfile() async {
    final hasFinancialHistory =
        products.isNotEmpty ||
        stocktakes.isNotEmpty ||
        purchases.isNotEmpty ||
        sales.isNotEmpty ||
        customerPayments.isNotEmpty ||
        refunds.isNotEmpty ||
        expenses.isNotEmpty ||
        cashMovements.isNotEmpty;
    final profile = await showDialog<BusinessProfile>(
      context: context,
      builder: (_) => BusinessProfileDialog(
        profile: _businessProfile,
        canChangeMarket: !hasFinancialHistory,
      ),
    );
    if (profile == null) return;
    setState(() {
      _businessProfile = profile;
      _activeCountryCode = profile.countryCode;
      _activeCurrencyCode = profile.currencyCode;
      _setActiveLanguage(profile.languageCode);
    });
    final synced = await _saveData();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            synced
                ? _tr(
                    'Réglages enregistrés • ${_marketOptions.firstWhere((market) => market.countryCode == _activeCountryCode).countryName} • $_currencyLabel',
                    'Settings saved • ${_marketOptions.firstWhere((market) => market.countryCode == _activeCountryCode).countryName} • $_currencyLabel',
                  )
                : _tr(
                    'Réglages enregistrés sur cet appareil. Synchronisation cloud en attente.',
                    'Settings saved on this device. Cloud sync is pending.',
                  ),
          ),
        ),
      );
    }
  }

  void _validateBackupSnapshot(Map<String, dynamic> data) {
    for (final key in ['receiptSequence', 'paymentSequence']) {
      final value = data[key];
      if (value != null &&
          (value is! num || !value.isFinite || value < 0 || value % 1 != 0)) {
        throw const FormatException(
          'Les numéros de reçus de la sauvegarde sont invalides.',
        );
      }
    }
    final parsers = <String, dynamic Function(Map<String, dynamic>)>{
      'products': Product.fromJson,
      'purchases': PurchaseRecord.fromJson,
      'suppliers': SupplierRecord.fromJson,
      'sales': SaleRecord.fromJson,
      'payments': PaymentRecord.fromJson,
      'refunds': RefundRecord.fromJson,
      'expenses': ExpenseRecord.fromJson,
      'stocktakes': StocktakeRecord.fromJson,
      'cashMovements': CashMovement.fromJson,
    };
    for (final entry in parsers.entries) {
      final records = data[entry.key];
      if (records is! List)
        throw const FormatException(
          'La sauvegarde est incomplète ou endommagée.',
        );
      try {
        for (final record in records) {
          if (record is! Map)
            throw const FormatException('Enregistrement invalide.');
          entry.value(Map<String, dynamic>.from(record));
        }
      } catch (_) {
        throw FormatException(
          'Une donnée de la sauvegarde est invalide (${entry.key}).',
        );
      }
    }
    final profile = data['businessProfile'];
    if (profile != null) {
      if (profile is! Map)
        throw const FormatException(
          'Les coordonnées du commerce sont invalides.',
        );
      try {
        BusinessProfile.fromJson(Map<String, dynamic>.from(profile));
      } catch (_) {
        throw const FormatException(
          'Les coordonnées du commerce sont invalides.',
        );
      }
    }
  }

  Future<void> _handleDataTransfer(String action) async {
    try {
      if (action == 'export') {
        final businessLabel = (_businessName ?? 'commerce').replaceAll(
          RegExp(r'[^a-zA-Z0-9_-]+'),
          '-',
        );
        final backup = {
          'app': 'BizGestion',
          'version': 1,
          'businessId': _businessId,
          'businessName': _businessName ?? 'Mon commerce',
          'exportedAt': DateTime.now().toIso8601String(),
          'data': _makeSnapshot(),
        };
        await downloadBusinessBackup(
          'BizGestion-$businessLabel-sauvegarde.json',
          const JsonEncoder.withIndent('  ').convert(backup),
        );
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('La sauvegarde JSON a été téléchargée.'),
            ),
          );
        return;
      }

      final contents = await pickBusinessBackupJson();
      if (contents == null || !mounted) return;
      if (contents.length > 50 * 1024 * 1024)
        throw const FormatException(
          'Ce fichier de sauvegarde dépasse la taille autorisée.',
        );
      final decoded = jsonDecode(contents);
      if (decoded is! Map ||
          decoded['app'] != 'BizGestion' ||
          decoded['version'] != 1 ||
          decoded['data'] is! Map) {
        throw const FormatException(
          'Ce fichier ne ressemble pas à une sauvegarde BizGestion.',
        );
      }
      final data = Map<String, dynamic>.from(decoded['data'] as Map);
      _validateBackupSnapshot(data);
      final sourceBusinessName =
          decoded['businessName']?.toString() ?? 'commerce inconnu';
      final sourceBusinessId = decoded['businessId']?.toString();
      final isDifferentBusiness =
          sourceBusinessId != null &&
          (_businessId == null || sourceBusinessId != _businessId);
      final targetBusinessName = _businessName ?? 'commerce actuel';
      if (isDifferentBusiness) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Sauvegarde d’un autre commerce'),
            content: Text(
              'Ce fichier appartient à « $sourceBusinessName », mais le commerce actuellement ouvert est « $targetBusinessName ».\n\n'
              'La restauration a été annulée : aucune donnée n’a été modifiée. Connecte-toi au commerce indiqué dans le fichier ou sélectionne la bonne sauvegarde.',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Compris'),
              ),
            ],
          ),
        );
        return;
      }
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Confirmer la restauration'),
          content: Text(
            'Commerce dans le fichier : « $sourceBusinessName ».\n'
            'Commerce qui sera remplacé : « $targetBusinessName ».\n\n'
            'Ses produits, ventes, achats, clients et autres données seront remplacés. Exporte d’abord une sauvegarde de ce commerce si tu veux pouvoir revenir en arrière.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Restaurer cette sauvegarde'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      setState(() => _restoreSnapshot(data));
      final synced = await _saveData();
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              synced ? 'Sauvegarde importée et synchronisée avec le cloud.' : 'Sauvegarde importée sur cet appareil; synchronisation cloud en attente.',
            ),
          ),
        );
    } on UnsupportedError catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error.message?.toString() ??
                  'Cette fonction n’est pas disponible sur cet appareil.',
            ),
          ),
        );
    } on FormatException catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message.toString())));
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Impossible de lire ou d’enregistrer cette sauvegarde.',
            ),
          ),
        );
      debugPrint('Transfert de données BizGestion impossible : $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 900;
        final isStaff = _businessRole == 'staff';
        final canManageStores =
            _businessRole == 'owner' &&
            _ownedBusinesses.any((business) => business.id == _businessId);
        final mobilePageIndexes = isStaff
            ? const [1, 3, 4]
            : const [0, 1, 2, 3, 4];
        final desktopPageIndexes = isStaff
            ? const [1, 3, 4]
            : <int>[0, 1, 2, 3, 4, 5, 6, 7, if (canManageStores) 8];
        final mobileSelectedIndex = mobilePageIndexes.indexOf(selectedIndex);

        final Widget page;
        if (selectedIndex == 1) {
          page = SalesContent(
            businessId: _businessId,
            payments: customerPayments,
            sales: sales,
            loadSalesPage: _loadSalesPage,
            refreshKey: _dataRefreshKey,
            products: products,
            onAddProduct: _addProduct,
            onNewSale: _addSale,
            onEditSale: _editSale,
            onCancelReceipt: _cancelSaleReceipt,
            onRefundSale: _refundSale,
            onMarkCollected: _markReceiptCollected,
            refunds: refunds,
            isStaff: isStaff,
            businessProfile: _businessProfile,
            businessName: _businessName ?? 'BizGestion',
          );
        } else if (selectedIndex == 2) {
          page = PurchaseContent(
            products: products,
            purchases: purchases,
            suppliers: suppliers,
            onAddProduct: _addProduct,
            onSavePurchase: _recordPurchase,
            onSaveSupplier: (supplier) {
              setState(() {
                final index = suppliers.indexWhere(
                  (item) =>
                      item.name.toLowerCase() == supplier.name.toLowerCase(),
                );
                if (index < 0) {
                  suppliers.insert(0, supplier);
                } else {
                  suppliers[index] = supplier;
                }
              });
              _saveData();
            },
          );
        } else if (selectedIndex == 3) {
          page = StockContent(
            products: products,
            isStaff: isStaff,
            onAdd: _addProduct,
            onEdit: _editProduct,
            stocktakes: stocktakes,
            onTakeStock: _takeStock,
            onRecordLoss: _recordStockLoss,
            onDelete: (product) async {
              final index = products.indexOf(product);
              if (index < 0) return;
              setState(() => products.removeAt(index));
              final saved = await _saveData();
              if (!saved && mounted) {
                setState(
                  () => products.insert(
                    index.clamp(0, products.length).toInt(),
                    product,
                  ),
                );
                final preferences = await SharedPreferences.getInstance();
                await preferences.setString(
                  _storageKey,
                  jsonEncode(_makeSnapshot()),
                );
                if (mounted)
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Suppression annulée : le produit n’a pas pu être synchronisé. Vérifie le cloud puis réessaie.',
                      ),
                    ),
                  );
              } else if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Produit supprimé du stock.')),
                );
              }
            },
          );
        } else if (selectedIndex == 4) {
          page = CustomerContent(
            businessName: _businessName ?? 'Mon commerce',
            sales: sales,
            payments: customerPayments,
            refunds: refunds,
            onCollectPayment: _collectCustomerPayment,
          );
        } else if (selectedIndex == 5) {
          page = ExpenseContent(expenses: expenses, onAddExpense: _addExpense);
        } else if (selectedIndex == 6) {
          page = ReportsContent(
            sales: sales,
            payments: customerPayments,
            purchases: purchases,
            expenses: expenses,
            refunds: refunds,
            products: products,
            cashMovements: cashMovements,
          );
        } else if (selectedIndex == 7) {
          page = CashContent(
            movements: cashMovements,
            sales: sales,
            payments: customerPayments,
            purchases: purchases,
            expenses: expenses,
            refunds: refunds,
            onAddMovement: _addCashMovement,
            onDeleteMovement: _removeCashMovement,
          );
        } else if (selectedIndex == 8 && canManageStores) {
          page = MultiStoreOverviewContent(
            businesses: _ownedBusinesses,
            isCreating: _creatingBusiness,
            onCreate: _createBusinessBranch,
            onOpenBusiness: (businessId) async {
              await _chooseBusiness(businessId);
              if (mounted) setState(() => selectedIndex = 0);
            },
          );
        } else if (selectedIndex == 0) {
          page = DashboardContent(
            businessId: _businessId,
            isDesktop: isDesktop,
            currentPage: pages[selectedIndex],
            selectedPeriod: _dashboardPeriod,
            onPeriodChanged: (period) =>
                setState(() => _dashboardPeriod = period),
            products: products,
            purchases: purchases,
            payments: customerPayments,
            refunds: refunds,
            cashMovements: cashMovements,
            canUseOnlineAI: _businessRole == 'owner',
            canSeeFullData: _businessRole != 'staff',
            canManageData: _businessRole == 'owner' || _businessRole == 'admin',
            onAddProduct: _addProduct,
            sales: sales,
            expenses: expenses,
            onOpenStock: () => setState(() => selectedIndex = 3),
            onOpenPurchases: () => setState(() => selectedIndex = 2),
            onOpenSales: () => setState(() => selectedIndex = 1),
            onOpenCustomers: () => setState(() => selectedIndex = 4),
            onOpenExpenses: () => setState(() => selectedIndex = 5),
            onExportBackup: () => _handleDataTransfer('export'),
          );
        } else {
          page = DashboardContent(
            businessId: _businessId,
            isDesktop: isDesktop,
            currentPage: pages[selectedIndex],
            selectedPeriod: _dashboardPeriod,
            onPeriodChanged: (period) =>
                setState(() => _dashboardPeriod = period),
            products: products,
            purchases: purchases,
            payments: customerPayments,
            refunds: refunds,
            cashMovements: cashMovements,
            canUseOnlineAI: _businessRole == 'owner',
            canSeeFullData: _businessRole != 'staff',
            canManageData: _businessRole == 'owner' || _businessRole == 'admin',
            onAddProduct: _addProduct,
            sales: sales,
            expenses: expenses,
            onOpenStock: () => setState(() => selectedIndex = 3),
            onOpenPurchases: () => setState(() => selectedIndex = 2),
            onOpenSales: () => setState(() => selectedIndex = 1),
            onOpenCustomers: () => setState(() => selectedIndex = 4),
            onOpenExpenses: () => setState(() => selectedIndex = 5),
            onExportBackup: () => _handleDataTransfer('export'),
          );
        }

        return Scaffold(
          appBar: AppBar(
            backgroundColor: Colors.white,
            title: Row(
              children: [
                Image.asset(
                  'assets/branding/bizgestion-logo.png',
                  width: 32,
                  height: 32,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    _businessName ?? 'BizGestion',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: ink,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              if (isDesktop &&
                  (_businessRole == 'owner' || _businessRole == 'admin'))
                IconButton(
                  tooltip: 'Réglages du commerce et des reçus',
                  onPressed: _editBusinessProfile,
                  icon: const Icon(Icons.settings_outlined, color: teal),
                ),
              if (isDesktop && _businessRole == 'owner')
                IconButton(
                  tooltip: 'Abonnement BizGestion',
                  onPressed: _openSubscription,
                  icon: const Icon(
                    Icons.workspace_premium_outlined,
                    color: navy,
                  ),
                ),
              if (isDesktop &&
                  (_businessRole == 'owner' || _businessRole == 'admin'))
                PopupMenuButton<String>(
                  tooltip: 'Sauvegarde des données',
                  icon: const Icon(Icons.swap_vert_rounded, color: teal),
                  onSelected: _handleDataTransfer,
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'export',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.download_outlined),
                        title: Text('Exporter une sauvegarde'),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'import',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.upload_file_outlined),
                        title: Text('Restaurer une sauvegarde'),
                      ),
                    ),
                  ],
                ),
              if (isDesktop && _businessAccess.length > 1)
                PopupMenuButton<String>(
                  tooltip: 'Changer de commerce',
                  icon: const Icon(
                    Icons.store_mall_directory_outlined,
                    color: navy,
                  ),
                  onSelected: _chooseBusiness,
                  itemBuilder: (_) => _businessAccess
                      .map(
                        (business) => PopupMenuItem<String>(
                          value: business.id,
                          child: Row(
                            children: [
                              Expanded(child: Text(business.name)),
                              const SizedBox(width: 12),
                              Text(
                                business.role == 'owner'
                                    ? 'Propriétaire'
                                    : business.role == 'admin'
                                    ? 'Admin'
                                    : 'Employé',
                                style: const TextStyle(
                                  color: Colors.black54,
                                  fontSize: 12,
                                ),
                              ),
                              if (business.id == _businessId)
                                const Padding(
                                  padding: EdgeInsets.only(left: 8),
                                  child: Icon(
                                    Icons.check,
                                    size: 18,
                                    color: teal,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                ),
              if (!isDesktop)
                PopupMenuButton<String>(
                  tooltip: 'Menu du commerce',
                  icon: const Icon(Icons.more_vert),
                  onSelected: (action) {
                    switch (action) {
                      case 'settings':
                        _editBusinessProfile();
                      case 'subscription':
                        _openSubscription();
                      case 'export':
                      case 'import':
                        _handleDataTransfer(action);
                      case 'team':
                        _openTeamManagement();
                      case 'activity':
                        _openActivityLog();
                      case 'guide':
                        _openStartupGuide();
                      case 'sync':
                        if (_syncError != null) {
                          _syncConflictNeedsChoice
                              ? _resolvePendingSyncConflict()
                              : _loadData();
                        }
                      case 'expenses':
                        setState(() => selectedIndex = 5);
                      case 'reports':
                        setState(() => selectedIndex = 6);
                      case 'cash':
                        setState(() => selectedIndex = 7);
                      case 'stores':
                        setState(() => selectedIndex = 8);
                      default:
                        if (action.startsWith('business:')) {
                          _chooseBusiness(action.substring('business:'.length));
                        }
                    }
                  },
                  itemBuilder: (_) => <PopupMenuEntry<String>>[
                    if (_businessRole == 'owner' || _businessRole == 'admin')
                      const PopupMenuItem(
                        value: 'settings',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.settings_outlined),
                          title: Text('Réglages du commerce'),
                        ),
                      ),
                    if (_businessRole == 'owner')
                      const PopupMenuItem(
                        value: 'subscription',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.workspace_premium_outlined),
                          title: Text('Abonnement'),
                        ),
                      ),
                    if (canManageStores)
                      const PopupMenuItem(
                        value: 'stores',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.store_mall_directory_outlined),
                          title: Text('Mes boutiques'),
                        ),
                      ),
                    if (_businessRole == 'owner' ||
                        _businessRole == 'admin') ...[
                      const PopupMenuItem(
                        value: 'export',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.download_outlined),
                          title: Text('Exporter une sauvegarde'),
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'import',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.upload_file_outlined),
                          title: Text('Restaurer une sauvegarde'),
                        ),
                      ),
                    ],
                    if (_businessAccess.length > 1) ...[
                      const PopupMenuDivider(),
                      ..._businessAccess.map(
                        (business) => PopupMenuItem<String>(
                          value: 'business:${business.id}',
                          child: Row(
                            children: [
                              Expanded(child: Text(business.name)),
                              if (business.id == _businessId)
                                const Icon(Icons.check, size: 18, color: teal),
                            ],
                          ),
                        ),
                      ),
                    ],
                    if (!isStaff) ...[
                      const PopupMenuDivider(),
                      const PopupMenuItem(
                        value: 'expenses',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.receipt_long_outlined),
                          title: Text('Dépenses'),
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'reports',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.bar_chart_outlined),
                          title: Text('Rapports'),
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'cash',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.account_balance_wallet_outlined),
                          title: Text('Caisse'),
                        ),
                      ),
                    ],
                    if (_businessRole == 'owner' ||
                        _businessRole == 'admin') ...[
                      const PopupMenuDivider(),
                      const PopupMenuItem(
                        value: 'team',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.group_outlined),
                          title: Text('Gérer les membres'),
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'activity',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.history_rounded),
                          title: Text('Journal d’activité'),
                        ),
                      ),
                    ],
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: 'guide',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.menu_book_outlined),
                        title: Text('Guide de démarrage'),
                      ),
                    ),
                    PopupMenuItem<String>(
                      value: 'sync',
                      enabled: _syncError != null,
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          _syncError == null
                              ? Icons.cloud_done_outlined
                              : Icons.cloud_off_outlined,
                          color: _syncError == null ? teal : Colors.deepOrange,
                        ),
                        title: Text(
                          _syncError == null
                              ? 'Cloud synchronisé'
                              : 'Réessayer la synchronisation',
                        ),
                      ),
                    ),
                  ],
                ),
              if (isDesktop &&
                  (_businessRole == 'owner' || _businessRole == 'admin'))
                IconButton(
                  tooltip: 'Gérer les membres du commerce',
                  onPressed: _openTeamManagement,
                  icon: const Icon(Icons.group_outlined, color: teal),
                ),
              if (isDesktop &&
                  (_businessRole == 'owner' || _businessRole == 'admin'))
                IconButton(
                  tooltip: 'Voir le journal d’activité',
                  onPressed: _openActivityLog,
                  icon: const Icon(Icons.history_rounded, color: teal),
                ),
              if (isDesktop)
                IconButton(
                  tooltip: _syncError == null && _businessId != null
                      ? 'Données synchronisées avec le cloud BizGestion'
                      : _syncError == null
                      ? 'Connexion au cloud en cours'
                      : _syncConflictNeedsChoice
                      ? 'Conflit de synchronisation — choisir une version'
                      : 'Synchronisation en erreur — appuie pour réessayer',
                  onPressed: _syncError == null
                      ? null
                      : _syncConflictNeedsChoice
                      ? _resolvePendingSyncConflict
                      : _loadData,
                  icon: Icon(
                    _syncError == null && _businessId != null
                        ? Icons.cloud_done_outlined
                        : Icons.cloud_off_outlined,
                    color: _syncError == null && _businessId != null
                        ? teal
                        : Colors.deepOrange,
                  ),
                ),
              IconButton(
                tooltip: _tr(
                  'Se déconnecter (${widget.email})',
                  'Sign out (${widget.email})',
                ),
                padding: const EdgeInsets.only(right: 20),
                onPressed: _confirmSignOut,
                icon: const CircleAvatar(
                  backgroundColor: Color(0xFFE2F2F0),
                  child: Icon(Icons.logout, color: teal),
                ),
              ),
            ],
          ),
          body: Row(
            children: [
              if (isDesktop)
                NavigationRail(
                  selectedIndex: desktopPageIndexes
                      .indexOf(selectedIndex)
                      .clamp(0, desktopPageIndexes.length - 1)
                      .toInt(),
                  onDestinationSelected: (index) {
                    setState(() => selectedIndex = desktopPageIndexes[index]);
                  },
                  labelType: NavigationRailLabelType.all,
                  backgroundColor: Colors.white,
                  destinations: desktopPageIndexes
                      .map(
                        (index) => switch (index) {
                          0 => NavigationRailDestination(
                            icon: Icon(Icons.dashboard_outlined),
                            label: Text(_tr('Accueil', 'Home')),
                          ),
                          1 => NavigationRailDestination(
                            icon: Icon(Icons.point_of_sale_outlined),
                            label: Text(_tr('Ventes', 'Sales')),
                          ),
                          2 => NavigationRailDestination(
                            icon: Icon(Icons.shopping_bag_outlined),
                            label: Text(_tr('Achats', 'Purchases')),
                          ),
                          3 => NavigationRailDestination(
                            icon: Icon(Icons.inventory_2_outlined),
                            label: Text(_tr('Stock', 'Inventory')),
                          ),
                          4 => NavigationRailDestination(
                            icon: Icon(Icons.people_outline),
                            label: Text(_tr('Clients', 'Customers')),
                          ),
                          5 => NavigationRailDestination(
                            icon: Icon(Icons.receipt_long_outlined),
                            label: Text(_tr('Dépenses', 'Expenses')),
                          ),
                          6 => NavigationRailDestination(
                            icon: Icon(Icons.bar_chart_outlined),
                            label: Text(_tr('Rapports', 'Reports')),
                          ),
                          7 => NavigationRailDestination(
                            icon: Icon(Icons.account_balance_wallet_outlined),
                            label: Text(_tr('Caisse', 'Cash register')),
                          ),
                          8 => NavigationRailDestination(
                            icon: Icon(Icons.store_mall_directory_outlined),
                            label: Text(_tr('Boutiques', 'Stores')),
                          ),
                          _ => NavigationRailDestination(
                            icon: Icon(Icons.account_balance_wallet_outlined),
                            label: Text(_tr('Caisse', 'Cash register')),
                          ),
                        },
                      )
                      .toList(),
                ),
              Expanded(
                child: Column(
                  children: [
                    if (_syncError != null)
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final isCompact = true;
                          final actionLabel = _syncConflictNeedsChoice
                              ? _tr('Résoudre', 'Resolve')
                              : _tr('Réessayer', 'Retry');
                          if (isCompact) {
                            final message = _syncConflictNeedsChoice
                                ? _tr(
                                    'Conflit cloud : choisis une version.',
                                    'Cloud conflict: choose a version.',
                                  )
                                : _tr(
                                    'Cloud indisponible : modifications gardées ici.',
                                    'Cloud unavailable: changes kept here.',
                                  );
                            return Material(
                              color: const Color(0xFFFFF4E5),
                              child: Container(
                                constraints: const BoxConstraints(
                                  minHeight: 42,
                                  maxHeight: 48,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 2,
                                ),
                                decoration: const BoxDecoration(
                                  border: Border(
                                    bottom: BorderSide(
                                      color: Color(0xFFFFD6A5),
                                    ),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.cloud_off_outlined,
                                      color: Colors.deepOrange,
                                      size: 22,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        message,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: _tr('Détails', 'Details'),
                                      visualDensity: VisualDensity.compact,
                                      constraints:
                                          const BoxConstraints.tightFor(
                                            width: 38,
                                            height: 38,
                                          ),
                                      padding: EdgeInsets.zero,
                                      onPressed: _showSyncErrorDetails,
                                      icon: const Icon(Icons.info_outline),
                                    ),
                                    IconButton(
                                      tooltip: actionLabel,
                                      visualDensity: VisualDensity.compact,
                                      constraints:
                                          const BoxConstraints.tightFor(
                                            width: 38,
                                            height: 38,
                                          ),
                                      padding: EdgeInsets.zero,
                                      onPressed: _syncConflictNeedsChoice
                                          ? _resolvePendingSyncConflict
                                          : _loadData,
                                      icon: Icon(
                                        _syncConflictNeedsChoice
                                            ? Icons.rule
                                            : Icons.refresh,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }
                          return MaterialBanner(
                            content: Text(_localizedSyncError(_syncError!)),
                            leading: const Icon(
                              Icons.cloud_off_outlined,
                              color: Colors.deepOrange,
                            ),
                            actions: [
                              TextButton(
                                onPressed: _showSyncErrorDetails,
                                child: Text(_tr('Détails', 'Details')),
                              ),
                              TextButton(
                                onPressed: _syncConflictNeedsChoice
                                    ? _resolvePendingSyncConflict
                                    : _loadData,
                                child: Text(actionLabel),
                              ),
                            ],
                          );
                        },
                      ),
                    Expanded(child: page),
                  ],
                ),
              ),
            ],
          ),
          bottomNavigationBar: isDesktop
              ? null
              : NavigationBar(
                  selectedIndex: mobileSelectedIndex < 0
                      ? 0
                      : mobileSelectedIndex,
                  onDestinationSelected: (index) {
                    setState(() => selectedIndex = mobilePageIndexes[index]);
                  },
                  destinations: mobilePageIndexes
                      .map(
                        (index) => switch (index) {
                          0 => NavigationDestination(
                            icon: Icon(Icons.dashboard_outlined),
                            label: _tr('Accueil', 'Home'),
                          ),
                          1 => NavigationDestination(
                            icon: Icon(Icons.point_of_sale_outlined),
                            label: _tr('Ventes', 'Sales'),
                          ),
                          2 => NavigationDestination(
                            icon: Icon(Icons.shopping_bag_outlined),
                            label: _tr('Achats', 'Purchases'),
                          ),
                          3 => NavigationDestination(
                            icon: Icon(Icons.inventory_2_outlined),
                            label: _tr('Stock', 'Inventory'),
                          ),
                          _ => NavigationDestination(
                            icon: Icon(Icons.people_outline),
                            label: _tr('Clients', 'Customers'),
                          ),
                        },
                      )
                      .toList(),
                ),
        );
      },
    );
  }

  @override
  void dispose() {
    _browserOnlineEvents.dispose();
    final channel = _businessUpdatesChannel;
    if (channel != null) Supabase.instance.client.removeChannel(channel);
    super.dispose();
  }
}

class SubscriptionPage extends StatefulWidget {
  const SubscriptionPage({
    super.key,
    required this.businessId,
    required this.businessName,
    required this.canManageSubscription,
    required this.currencyCode,
    required this.productsUsed,
    required this.salesUsedThisMonth,
    required this.totalSalesCount,
  });

  final String businessId;
  final String businessName;
  final bool canManageSubscription;
  final String currencyCode;
  final int productsUsed;
  final int salesUsedThisMonth;
  final int totalSalesCount;

  @override
  State<SubscriptionPage> createState() => _SubscriptionPageState();
}

class _SubscriptionPageState extends State<SubscriptionPage> {
  late Future<Map<String, dynamic>?> _subscription = _loadSubscription();
  String? _payingPlan;
  StreamSubscription<List<PurchaseDetails>>? _playPurchaseUpdates;
  bool _playStoreAvailable = false;
  bool _loadingPlayProducts = false;
  final Map<String, ProductDetails> _playProducts = {};
  String? _playBillingMessage;

  bool get _usesGooglePlayBilling =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  bool get _paypalCheckoutAvailable =>
      _paypalCheckoutEnabled && !_usesGooglePlayBilling;

  String _googlePlayPrice(String productId) {
    if (_loadingPlayProducts)
      return _tr('Chargement du prix…', 'Loading price…');
    return _playProducts[productId]?.price ??
        _tr('Prix Play Store indisponible', 'Play Store price unavailable');
  }

  @override
  void initState() {
    super.initState();
    if (_usesGooglePlayBilling) {
      _playPurchaseUpdates = InAppPurchase.instance.purchaseStream.listen(
        _handleGooglePlayPurchaseUpdates,
        onError: (Object error) {
          if (mounted) {
            setState(() => _playBillingMessage = error.toString());
          }
        },
      );
      _loadGooglePlayProducts();
    }
  }

  @override
  void dispose() {
    _playPurchaseUpdates?.cancel();
    super.dispose();
  }

  Future<void> _loadGooglePlayProducts() async {
    if (!_usesGooglePlayBilling) return;
    setState(() => _loadingPlayProducts = true);
    try {
      final available = await InAppPurchase.instance.isAvailable();
      if (!available) {
        if (mounted) {
          setState(() {
            _playStoreAvailable = false;
            _loadingPlayProducts = false;
            _playBillingMessage = _tr(
              'Google Play Billing est indisponible sur cet appareil.',
              'Google Play Billing is unavailable on this device.',
            );
          });
        }
        return;
      }
      final response = await InAppPurchase.instance.queryProductDetails(
        _googlePlaySubscriptionProducts,
      );
      if (!mounted) return;
      setState(() {
        _playStoreAvailable = true;
        _loadingPlayProducts = false;
        _playProducts
          ..clear()
          ..addEntries(
            response.productDetails.map((item) => MapEntry(item.id, item)),
          );
        _playBillingMessage = response.notFoundIDs.isEmpty
            ? null
            : _tr(
                'Les abonnements doivent d’abord être créés et activés dans Google Play Console.',
                'Subscriptions must first be created and activated in Google Play Console.',
              );
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _playStoreAvailable = false;
        _loadingPlayProducts = false;
        _playBillingMessage = error.toString();
      });
    }
  }

  Future<void> _startGooglePlayCheckout(String productId) async {
    final product = _playProducts[productId];
    if (!widget.canManageSubscription ||
        !_usesGooglePlayBilling ||
        !_playStoreAvailable ||
        product == null ||
        _payingPlan != null) {
      return;
    }
    setState(() {
      _payingPlan = productId;
      _playBillingMessage = null;
    });
    try {
      if (product is! GooglePlayProductDetails || product.offerToken == null) {
        throw StateError(
          _tr(
            'Aucune offre d’abonnement Google Play active pour ce forfait.',
            'No active Google Play subscription offer exists for this plan.',
          ),
        );
      }
      final launched = await InAppPurchase.instance.buyNonConsumable(
        purchaseParam: GooglePlayPurchaseParam(
          productDetails: product,
          offerToken: product.offerToken,
          applicationUserName: widget.businessId,
          obfuscatedProfileId: widget.businessId,
        ),
      );
      if (!launched && mounted) {
        setState(() {
          _payingPlan = null;
          _playBillingMessage = _tr(
            'Google Play n’a pas pu ouvrir la fenêtre d’abonnement.',
            'Google Play could not open the subscription sheet.',
          );
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _payingPlan = null;
        _playBillingMessage = error.toString();
      });
    }
  }

  Future<void> _restoreGooglePlayPurchases() async {
    if (!widget.canManageSubscription ||
        !_usesGooglePlayBilling ||
        !_playStoreAvailable)
      return;
    try {
      await InAppPurchase.instance.restorePurchases();
    } catch (error) {
      if (mounted) setState(() => _playBillingMessage = error.toString());
    }
  }

  Future<void> _handleGooglePlayPurchaseUpdates(
    List<PurchaseDetails> purchases,
  ) async {
    for (final purchase in purchases) {
      if (purchase.status == PurchaseStatus.pending) {
        if (mounted) setState(() => _payingPlan = purchase.productID);
        continue;
      }
      if (purchase.status == PurchaseStatus.error) {
        if (mounted) {
          setState(() {
            _payingPlan = null;
            _playBillingMessage =
                purchase.error?.message ??
                _tr(
                  'L’achat Google Play a échoué.',
                  'Google Play purchase failed.',
                );
          });
        }
        continue;
      }
      if (purchase.status != PurchaseStatus.purchased &&
          purchase.status != PurchaseStatus.restored) {
        if (purchase.pendingCompletePurchase) {
          await InAppPurchase.instance.completePurchase(purchase);
        }
        if (mounted) setState(() => _payingPlan = null);
        continue;
      }

      try {
        final response = await Supabase.instance.client.functions.invoke(
          'verify-google-play-subscription',
          body: {
            'business_id': widget.businessId,
            'product_id': purchase.productID,
            'purchase_token': purchase.verificationData.serverVerificationData,
          },
        );
        final payload = response.data is Map
            ? Map<String, dynamic>.from(response.data as Map)
            : <String, dynamic>{};
        if (response.status < 200 ||
            response.status >= 300 ||
            payload['verified'] != true) {
          throw StateError(
            payload['error']?.toString() ??
                _tr(
                  'Google Play n’a pas confirmé cet abonnement.',
                  'Google Play did not confirm this subscription.',
                ),
          );
        }
        if (purchase.pendingCompletePurchase) {
          await InAppPurchase.instance.completePurchase(purchase);
        }
        if (!mounted) return;
        setState(() {
          _payingPlan = null;
          _playBillingMessage = _tr(
            'Abonnement vérifié par Google Play.',
            'Subscription verified by Google Play.',
          );
          _subscription = _loadSubscription();
        });
      } catch (error) {
        if (!mounted) return;
        setState(() {
          _payingPlan = null;
          _playBillingMessage = error.toString().replaceFirst(
            'Bad state: ',
            '',
          );
        });
      }
    }
  }

  String _planPrice(int amountUsd) => '\$$amountUsd USD';

  Future<Map<String, dynamic>?> _loadSubscription() async {
    final row = await Supabase.instance.client
        .from('business_subscriptions')
        .select(
          'plan_code, status, trial_started_at, trial_ends_at, current_period_end, payment_provider, provider_environment',
        )
        .eq('business_id', widget.businessId)
        .maybeSingle();
    return row == null ? null : Map<String, dynamic>.from(row);
  }

  Future<void> _startPayPalCheckout(
    String planCode,
    String billingPeriod,
  ) async {
    if (!_paypalCheckoutAvailable || _payingPlan != null) return;
    final planKey = '${planCode}_$billingPeriod';
    setState(() => _payingPlan = planKey);
    try {
      final response = await Supabase.instance.client.functions.invoke(
        'create-paypal-subscription',
        body: {
          'business_id': widget.businessId,
          'plan_code': planCode,
          'billing_period': billingPeriod,
          'paypal_environment': _paypalLiveCheckoutEnabled ? 'live' : 'sandbox',
        },
      );
      final payload = response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : <String, dynamic>{};
      if (response.status < 200 || response.status >= 300) {
        throw StateError(
          payload['error']?.toString() ?? 'PayPal indisponible.',
        );
      }
      final expectedEnvironment = _paypalLiveCheckoutEnabled
          ? 'live'
          : 'sandbox';
      if (payload['environment'] != expectedEnvironment) {
        throw StateError(
          'L’environnement PayPal du serveur ne correspond pas à cette version de BizGestion. Aucun paiement n’a été ouvert.',
        );
      }
      if (payload['plan_code'] != planCode ||
          payload['billing_period'] != billingPeriod) {
        throw StateError(
          'Le service PayPal a préparé un autre forfait que celui choisi. Aucun paiement n’a été ouvert. Recharge BizGestion et redéploie la fonction create-paypal-subscription.',
        );
      }
      final approvalUrl = Uri.tryParse(
        payload['approval_url']?.toString() ?? '',
      );
      if (approvalUrl == null ||
          approvalUrl.scheme != 'https' ||
          !approvalUrl.host.endsWith('paypal.com')) {
        throw StateError(
          'PayPal n’a pas renvoyé un lien d’approbation valide.',
        );
      }
      final opened = await launchUrl(
        approvalUrl,
        mode: LaunchMode.externalApplication,
      );
      if (!opened) throw StateError('Impossible d’ouvrir la page PayPal.');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _paypalLiveCheckoutEnabled
                  ? _tr(
                      'Termine le paiement dans PayPal, puis reviens ici et actualise le forfait.',
                      'Finish checkout in PayPal, then return here and refresh the plan status.',
                    )
                  : _tr(
                      'Termine le paiement de test dans PayPal, puis reviens ici et actualise le forfait.',
                      'Finish the test checkout in PayPal, then return here and refresh the plan status.',
                    ),
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        final message = error is FunctionException
            ? (error.details is Map
                      ? (error.details as Map)['error']?.toString()
                      : null) ??
                  error.reasonPhrase ??
                  error.toString()
            : error.toString().replaceFirst('Bad state: ', '');
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _payingPlan = null);
    }
  }

  String _dateValue(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '');
    if (date == null) return '—';
    if (_activeLanguageCode == 'en') {
      return '${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}/${date.year}';
    }
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Abonnement BizGestion'),
      actions: [
        IconButton(
          tooltip: 'Actualiser',
          onPressed: () {
            setState(() => _subscription = _loadSubscription());
          },
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1280),
        child: FutureBuilder<Map<String, dynamic>?>(
          future: _subscription,
          builder: (context, snapshot) {
            final row = snapshot.data;
            final expectedEnvironment = _paypalLiveCheckoutEnabled
                ? 'live'
                : 'sandbox';
            final staleSandboxPlan =
                _paypalCheckoutEnabled &&
                row?['payment_provider'] == 'paypal' &&
                (row?['provider_environment']?.toString() ?? 'sandbox') !=
                    expectedEnvironment;
            final planCode = staleSandboxPlan
                ? 'trial'
                : row?['plan_code']?.toString() ?? 'trial';
            final status = staleSandboxPlan
                ? 'trialing'
                : row?['status']?.toString() ?? 'trialing';
            final trialEnds = DateTime.tryParse(
              row?['trial_ends_at']?.toString() ?? '',
            );
            final daysLeft = trialEnds == null
                ? null
                : DateTime(
                    trialEnds.year,
                    trialEnds.month,
                    trialEnds.day,
                  ).difference(DateTime.now()).inDays;
            final currentPlan = switch (planCode) {
              'decouverte' => 'Découverte',
              'commerce' => 'Commerce',
              'entreprise' => 'Entreprise',
              _ => 'Essai gratuit',
            };
            final trialLimit = planCode == 'trial';
            final statusLabel =
                status == 'trialing' && daysLeft != null && daysLeft < 0
                ? 'Essai terminé'
                : status == 'trialing'
                ? 'Période d’essai'
                : status == 'active'
                ? 'Actif'
                : status == 'past_due'
                ? _tr('Paiement à régulariser', 'Payment past due')
                : status == 'suspended'
                ? _tr('Suspendu', 'Suspended')
                : status == 'canceled'
                ? _tr('Résilié', 'Canceled')
                : status == 'expired'
                ? 'Terminé'
                : 'Suspendu';
            final productLimit = switch (planCode) {
              'commerce' => 500,
              'entreprise' => 5000,
              _ => 50,
            };
            final salesLimit = switch (planCode) {
              'commerce' => 10000,
              'entreprise' => 100000,
              _ => 500,
            };
            final memberLimit = switch (planCode) {
              'commerce' => 10,
              'entreprise' => 50,
              // The SQL enforcement grants five seats to both trial and
              // Découverte plans; keep the displayed limit in sync with it.
              'trial' || 'decouverte' => 5,
              _ => 5,
            };
            final planCards = <Widget>[
              _SubscriptionPlanCard(
                title: 'Découverte',
                subtitle: 'Pour démarrer seul',
                icon: Icons.storefront_outlined,
                price: _tr('Gratuit', 'Free'),
                limits:
                    '50 produits • 500 reçus/mois • 5 membres • 2 boutiques',
                features: [
                  'Gestion complète du commerce',
                  'Stock, achats, ventes et dépenses',
                  'Suivi des clients et sauvegardes',
                  _tr(
                    'Assistant hors ligne pour toute l’équipe • IA en ligne : 5 questions/jour pour le propriétaire',
                    'Offline assistant for the whole team • Online AI: 5 questions/day for the owner',
                  ),
                ],
              ),
              _SubscriptionPlanCard(
                title: 'Commerce',
                subtitle: 'Pour une équipe active',
                icon: Icons.groups_outlined,
                price: _usesGooglePlayBilling
                    ? _googlePlayPrice('bizgestion_commerce_monthly')
                    : '${_planPrice(4)} ${_tr('/ mois', '/ month')}',
                annualPrice: _usesGooglePlayBilling
                    ? '${_googlePlayPrice('bizgestion_commerce_annual')} ${_tr('/ an', '/ year')}'
                    : '${_planPrice(40)} ${_tr('/ an • 2 mois offerts', '/ year • 2 months free')}',
                limits: '500 produits • 10 000 reçus/mois • 10 membres • 4 boutiques',
                features: [
                  'Toutes les fonctions de Découverte',
                  'Gestion d’équipe',
                  'Rapports et suivi avancé',
                  _tr(
                    'IA en ligne du propriétaire • jusqu’à 1 695 questions/mois',
                    'Owner online AI • up to 1,695 questions/month',
                  ),
                  _tr(
                    'Assistant hors ligne disponible pour les employés',
                    'Offline assistant available to staff',
                  ),
                ],
                monthlyAction: _usesGooglePlayBilling
                    ? status != 'active' &&
                              _playProducts.containsKey(
                                'bizgestion_commerce_monthly',
                              )
                          ? () => _startGooglePlayCheckout(
                              'bizgestion_commerce_monthly',
                            )
                          : null
                    : _paypalCheckoutAvailable && status != 'active'
                    ? () => _startPayPalCheckout('commerce', 'monthly')
                    : null,
                annualAction: _usesGooglePlayBilling
                    ? status != 'active' &&
                              _playProducts.containsKey(
                                'bizgestion_commerce_annual',
                              )
                          ? () => _startGooglePlayCheckout(
                              'bizgestion_commerce_annual',
                            )
                          : null
                    : _paypalCheckoutAvailable && status != 'active'
                    ? () => _startPayPalCheckout('commerce', 'annual')
                    : null,
                monthlyBusy: _payingPlan == 'bizgestion_commerce_monthly',
                annualBusy: _payingPlan == 'bizgestion_commerce_annual',
                playBilling: _usesGooglePlayBilling,
                showPurchaseOptions:
                    status != 'active' && widget.canManageSubscription,
              ),
              _SubscriptionPlanCard(
                title: 'Entreprise',
                subtitle: 'Pour une activité à grande échelle',
                icon: Icons.business_outlined,
                price: _usesGooglePlayBilling
                    ? _googlePlayPrice('bizgestion_entreprise_monthly')
                    : '${_planPrice(12)} ${_tr('/ mois', '/ month')}',
                annualPrice: _usesGooglePlayBilling
                    ? '${_googlePlayPrice('bizgestion_entreprise_annual')} ${_tr('/ an', '/ year')}'
                    : '${_planPrice(120)} ${_tr('/ an • 2 mois offerts', '/ year • 2 months free')}',
                limits: '5 000 produits • 100 000 reçus/mois • 50 membres • 8 boutiques',
                features: [
                  'Toutes les fonctions de Commerce',
                  'Plusieurs commerces accessibles par compte',
                  'Accompagnement et options avancées',
                  _tr(
                    'IA en ligne du propriétaire • jusqu’à 2 825 questions/mois',
                    'Owner online AI • up to 2,825 questions/month',
                  ),
                  _tr(
                    'Assistant hors ligne disponible pour les employés',
                    'Offline assistant available to staff',
                  ),
                ],
                monthlyAction: _usesGooglePlayBilling
                    ? status != 'active' &&
                              _playProducts.containsKey(
                                'bizgestion_entreprise_monthly',
                              )
                          ? () => _startGooglePlayCheckout(
                              'bizgestion_entreprise_monthly',
                            )
                          : null
                    : _paypalCheckoutAvailable && status != 'active'
                    ? () => _startPayPalCheckout('entreprise', 'monthly')
                    : null,
                annualAction: _usesGooglePlayBilling
                    ? status != 'active' &&
                              _playProducts.containsKey(
                                'bizgestion_entreprise_annual',
                              )
                          ? () => _startGooglePlayCheckout(
                              'bizgestion_entreprise_annual',
                            )
                          : null
                    : _paypalCheckoutAvailable && status != 'active'
                    ? () => _startPayPalCheckout('entreprise', 'annual')
                    : null,
                monthlyBusy: _payingPlan == 'bizgestion_entreprise_monthly',
                annualBusy: _payingPlan == 'bizgestion_entreprise_annual',
                playBilling: _usesGooglePlayBilling,
                showPurchaseOptions:
                    status != 'active' && widget.canManageSubscription,
              ),
            ];
            return ListView(
              padding: EdgeInsets.all(
                MediaQuery.sizeOf(context).width < 600 ? 16 : 26,
              ),
              children: [
                _BizPageHero(
                  title: _tr(
                    'Ton abonnement BizGestion',
                    'Your BizGestion plan',
                  ),
                  subtitle: _tr(
                    'Choisis le forfait adapté à ton activité.',
                    'Choose the plan that fits your business.',
                  ),
                  icon: Icons.workspace_premium_rounded,
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const CircleAvatar(
                              backgroundColor: Color(0xFFE8EAFE),
                              child: Icon(
                                Icons.workspace_premium_outlined,
                                color: navy,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                widget.businessName,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: ink,
                                ),
                              ),
                            ),
                            if (snapshot.connectionState ==
                                ConnectionState.waiting)
                              const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (snapshot.connectionState == ConnectionState.waiting)
                          const Text(
                            'Chargement du forfait et de la période d’essai…',
                            style: TextStyle(color: Colors.black54),
                          )
                        else if (snapshot.hasError)
                          const Text(
                            'Le suivi SaaS n’est pas encore configuré dans Supabase. La migration d’abonnement doit être exécutée avant d’afficher l’état du forfait.',
                            style: TextStyle(
                              color: Color(0xFFB84A52),
                              height: 1.45,
                            ),
                          )
                        else if (row == null &&
                            snapshot.connectionState == ConnectionState.done)
                          const Text(
                            'Aucun forfait trouvé pour ce commerce. Exécute la migration SQL BizGestion pour démarrer le suivi.',
                            style: TextStyle(
                              color: Color(0xFFB84A52),
                              height: 1.45,
                            ),
                          )
                        else ...[
                          Text(
                            'Forfait actuel : $currentPlan • $statusLabel',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (_usesGooglePlayBilling && status == 'active') ...[
                            const SizedBox(height: 6),
                            Text(
                              _tr(
                                'Un abonnement est actif. Gérez son renouvellement dans Google Play.',
                                'A subscription is active. Manage renewal in Google Play.',
                              ),
                              style: const TextStyle(
                                color: Colors.black54,
                                height: 1.4,
                              ),
                            ),
                          ],
                          if (widget.canManageSubscription &&
                              _usesGooglePlayBilling) ...[
                            const SizedBox(height: 8),
                            TextButton.icon(
                              onPressed: _playStoreAvailable
                                  ? _restoreGooglePlayPurchases
                                  : null,
                              icon: const Icon(Icons.restore_rounded),
                              label: Text(
                                _tr(
                                  'Restaurer les achats Google Play',
                                  'Restore Google Play purchases',
                                ),
                              ),
                            ),
                          ],
                          if (_usesGooglePlayBilling &&
                              !widget.canManageSubscription) ...[
                            const SizedBox(height: 6),
                            Text(
                              _tr(
                                'Les achats d’abonnement sont réservés au propriétaire du commerce. Les employés peuvent utiliser l’assistant hors ligne.',
                                'Subscription purchases are reserved for the business owner. Staff can use the offline assistant.',
                              ),
                              style: const TextStyle(
                                color: Colors.black54,
                                height: 1.4,
                              ),
                            ),
                          ],
                          if (!_usesGooglePlayBilling &&
                              _paypalCheckoutEnabled &&
                              status == 'active') ...[
                            const SizedBox(height: 6),
                            Text(
                              _tr(
                                'Un forfait est déjà actif. Pour choisir un autre forfait, résilie d’abord celui-ci dans PayPal, puis actualise cette page.',
                                'A plan is already active. To choose another plan, cancel this one in PayPal first, then refresh this page.',
                              ),
                              style: const TextStyle(
                                color: Colors.black54,
                                height: 1.4,
                              ),
                            ),
                          ],
                          if (trialLimit && trialEnds != null) ...[
                            const SizedBox(height: 6),
                            Text(
                              daysLeft! >= 0
                                  ? 'Fin de l’essai : ${_dateValue(trialEnds)} • $daysLeft jour(s) restant(s)'
                                  : 'Essai terminé le ${_dateValue(trialEnds)}.',
                              style: TextStyle(
                                color: daysLeft < 0
                                    ? const Color(0xFFB84A52)
                                    : Colors.black54,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                          if (trialLimit &&
                              daysLeft != null &&
                              daysLeft < 0) ...[
                            const SizedBox(height: 8),
                            const Text(
                              'L’essai est arrivé à son terme. Les données restent accessibles pendant la préparation des forfaits payants; aucun paiement automatique n’est activé.',
                              style: TextStyle(
                                color: Color(0xFF8A5A00),
                                height: 1.4,
                              ),
                            ),
                          ],
                          const SizedBox(height: 14),
                          Text(
                            'Produits : ${widget.productsUsed} / $productLimit',
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Reçus ce mois-ci : ${widget.salesUsedThisMonth} / $salesLimit  •  ${widget.totalSalesCount} au total',
                          ),
                          const SizedBox(height: 4),
                          Text('Membres : maximum $memberLimit'),
                        ],
                        const SizedBox(height: 14),
                        Text(
                          _usesGooglePlayBilling
                              ? _tr(
                                  'Les abonnements Android passent par Google Play. Les prix affichés sont ceux de la boutique Play du pays du client.',
                                  'Android subscriptions use Google Play. Displayed prices come from the customer’s Play Store country.',
                                )
                              : _paypalLiveCheckoutEnabled
                              ? _tr(
                                  'Le paiement PayPal est en mode réel : l’abonnement sera facturé en USD selon le forfait choisi.',
                                  'PayPal checkout is live: the selected plan will be charged in USD.',
                                )
                              : _paypalSandboxCheckoutEnabled
                              ? _tr(
                                  'Le paiement PayPal est en mode test. Seuls les comptes PayPal Sandbox fonctionnent; aucun prélèvement réel ne sera fait.',
                                  'PayPal checkout is in test mode. Only PayPal Sandbox accounts work; no real charge will be made.',
                                )
                              : _tr(
                                  'Le paiement PayPal de test est désactivé. Aucun prélèvement ne sera effectué depuis cette page.',
                                  'PayPal test checkout is disabled. No payment will be charged from this page.',
                                ),
                          style: const TextStyle(
                            color: Colors.black54,
                            height: 1.4,
                          ),
                        ),
                        if (_usesGooglePlayBilling &&
                            _playBillingMessage != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            _playBillingMessage!,
                            style: const TextStyle(
                              color: Color(0xFF8A5A00),
                              height: 1.4,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Forfaits BizGestion',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                    color: ink,
                  ),
                ),
                const SizedBox(height: 10),
                LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth >= 1050) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (
                            var index = 0;
                            index < planCards.length;
                            index++
                          ) ...[
                            Expanded(child: planCards[index]),
                            if (index < planCards.length - 1)
                              const SizedBox(width: 12),
                          ],
                        ],
                      );
                    }
                    return Column(children: planCards);
                  },
                ),
                const SizedBox(height: 10),
                Card(
                  color: const Color(0xFFFFFCF4),
                  elevation: 3,
                  shadowColor: const Color(0x22D9A441),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22),
                    side: const BorderSide(color: Color(0xFFF0DCA9)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.local_offer_outlined,
                              color: Color(0xFFB27A18),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _tr(
                                  'À découvrir sur Chariow',
                                  'Discover on Chariow',
                                ),
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  color: ink,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF0C9),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                _tr('Offre indépendante', 'Separate offer'),
                                style: const TextStyle(
                                  color: Color(0xFF80570E),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _tr(
                            'Créer un compte PayPal depuis l’Afrique',
                            'Create a PayPal account from Africa',
                          ),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: ink,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '2 500 FCFA',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xff24318b),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _tr(
                            'Offre proposée par Chariow. Le formulaire complet s’ouvrira sur une page dédiée, avec défilement.',
                            'Offer provided by Chariow. The full checkout form will open on a separate scrollable page.',
                          ),
                          style: const TextStyle(color: Colors.black54),
                        ),
                        const SizedBox(height: 8),
                        buildChariowOfferWidget(),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _tr(
                    _paypalLiveCheckoutEnabled
                        ? 'Paiement PayPal réel activé : les abonnements sont facturés en USD. Vérifie soigneusement le forfait avant validation.'
                        : _paypalSandboxCheckoutEnabled
                        ? 'Paiement PayPal en mode Sandbox : seuls les comptes de test sont acceptés et aucun argent réel n’est prélevé. Les forfaits sont facturés en USD.'
                        : 'Les forfaits sont facturés en USD. Les paiements PayPal de test sont désactivés. En mode de développement, utilise PAYPAL_SANDBOX_ENABLED=true après le déploiement des fonctions Supabase.',
                    _paypalLiveCheckoutEnabled
                        ? 'Live PayPal checkout is enabled: subscriptions are billed in USD. Check the plan carefully before confirming.'
                        : _paypalSandboxCheckoutEnabled
                        ? 'PayPal Sandbox checkout: only test accounts are accepted and no real money is charged. Plans are billed in USD.'
                        : 'Plans are billed in USD. PayPal test checkout is disabled. In development, use PAYPAL_SANDBOX_ENABLED=true after deploying the Supabase functions.',
                  ),
                  style: TextStyle(color: Colors.black54, height: 1.5),
                ),
              ],
            );
          },
        ),
      ),
    ),
  );
}

class _CashOverviewValue extends StatelessWidget {
  const _CashOverviewValue({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, color: color, size: 20),
      const SizedBox(width: 8),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          Text(
            value,
            style: TextStyle(color: color, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    ],
  );
}

class _ReportBreakdownValue extends StatelessWidget {
  const _ReportBreakdownValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 110),
    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class _SubscriptionPlanCard extends StatelessWidget {
  const _SubscriptionPlanCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.price,
    this.annualPrice,
    required this.limits,
    required this.features,
    this.monthlyAction,
    this.annualAction,
    this.monthlyBusy = false,
    this.annualBusy = false,
    this.playBilling = false,
    this.showPurchaseOptions = true,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final String price;
  final String? annualPrice;
  final String limits;
  final List<String> features;
  final VoidCallback? monthlyAction;
  final VoidCallback? annualAction;
  final bool monthlyBusy;
  final bool annualBusy;
  final bool playBilling;
  final bool showPurchaseOptions;

  @override
  Widget build(BuildContext context) {
    // Keep Commerce and Entreprise in one coherent visual family.
    final accent = teal;
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 7,
      shadowColor: accent.withValues(alpha: .16),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: accent.withValues(alpha: .12)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: const [Color(0xFF173B73), Color(0xFF168E9B)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(15),
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: .2),
                    blurRadius: 12,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .18),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Icon(icon, color: Colors.white),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          subtitle,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: .82),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              price,
              style: TextStyle(
                color: accent,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (annualPrice != null) ...[
              const SizedBox(height: 2),
              Text(
                annualPrice!,
                style: const TextStyle(color: Colors.black54, fontSize: 13),
              ),
            ],
            const SizedBox(height: 10),
            Text(
              limits,
              style: TextStyle(fontWeight: FontWeight.w800, color: accent),
            ),
            const SizedBox(height: 6),
            ...features.map(
              (feature) => Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_outline, size: 18, color: accent),
                    const SizedBox(width: 8),
                    Expanded(child: Text(feature)),
                  ],
                ),
              ),
            ),
            if ((showPurchaseOptions && playBilling && annualPrice != null) ||
                (showPurchaseOptions &&
                    (monthlyAction != null ||
                        annualAction != null ||
                        (!_paypalCheckoutEnabled && annualPrice != null)))) ...[
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  if (showPurchaseOptions &&
                      (monthlyAction != null ||
                          (playBilling && annualPrice != null) ||
                          (!_paypalCheckoutEnabled &&
                              !playBilling &&
                              annualPrice != null)))
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.white,
                        elevation: 4,
                        shadowColor: accent.withValues(alpha: .35),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                      onPressed: monthlyBusy || annualBusy
                          ? null
                          : monthlyAction,
                      icon: playBilling
                          ? monthlyBusy
                                ? const SizedBox.square(
                                    dimension: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.shop_rounded)
                          : !_paypalCheckoutEnabled
                          ? const Icon(Icons.schedule_rounded)
                          : monthlyBusy
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.credit_card_rounded),
                      label: Text(
                        playBilling
                            ? _tr(
                                'S’abonner au mois avec Google Play',
                                'Subscribe monthly with Google Play',
                              )
                            : !_paypalCheckoutEnabled
                            ? _tr(
                                'Mensuel bientôt disponible',
                                'Monthly plan coming soon',
                              )
                            : _paypalLiveCheckoutEnabled
                            ? _tr(
                                'S’abonner mensuellement avec PayPal',
                                'Subscribe monthly with PayPal',
                              )
                            : _tr(
                                'Tester mensuellement avec PayPal',
                                'Test monthly with PayPal',
                              ),
                      ),
                    ),
                  if (showPurchaseOptions &&
                      (annualAction != null ||
                          (playBilling && annualPrice != null) ||
                          (!_paypalCheckoutEnabled &&
                              !playBilling &&
                              annualPrice != null)))
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: navy,
                        foregroundColor: Colors.white,
                        elevation: 4,
                        shadowColor: navy.withValues(alpha: .35),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                      onPressed: monthlyBusy || annualBusy
                          ? null
                          : annualAction,
                      icon: playBilling
                          ? annualBusy
                                ? const SizedBox.square(
                                    dimension: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.shop_rounded)
                          : !_paypalCheckoutEnabled
                          ? const Icon(Icons.schedule_rounded)
                          : annualBusy
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.event_repeat_rounded),
                      label: Text(
                        playBilling
                            ? _tr(
                                'S’abonner à l’année avec Google Play',
                                'Subscribe annually with Google Play',
                              )
                            : !_paypalCheckoutEnabled
                            ? _tr(
                                'Annuel bientôt disponible',
                                'Annual plan coming soon',
                              )
                            : _paypalLiveCheckoutEnabled
                            ? _tr(
                                'S’abonner annuellement avec PayPal',
                                'Subscribe annually with PayPal',
                              )
                            : _tr(
                                'Tester annuellement avec PayPal',
                                'Test annually with PayPal',
                              ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DashboardActivity {
  const _DashboardActivity({
    required this.date,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  final DateTime date;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
}

class _BusinessInsight {
  const _BusinessInsight({
    required this.icon,
    required this.title,
    required this.detail,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String detail;
  final Color color;
}

String _normalizeAssistantQuery(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'[àáâä]'), 'a')
    .replaceAll(RegExp(r'[èéêë]'), 'e')
    .replaceAll(RegExp(r'[ìíîï]'), 'i')
    .replaceAll(RegExp(r'[òóôö]'), 'o')
    .replaceAll(RegExp(r'[ùúûü]'), 'u')
    .replaceAll('ç', 'c')
    .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

class LocalAssistantCard extends StatefulWidget {
  const LocalAssistantCard({
    super.key,
    required this.businessId,
    required this.periodSales,
    required this.allSales,
    required this.products,
    required this.purchases,
    required this.payments,
    required this.expenses,
    required this.refunds,
    required this.cashMovements,
    required this.canUseOnlineAI,
    required this.canSeeFullData,
    required this.periodRevenue,
    required this.netProfit,
    required this.selectedPeriod,
  });

  final String? businessId;
  final List<SaleRecord> periodSales;
  final List<SaleRecord> allSales;
  final List<Product> products;
  final List<PurchaseRecord> purchases;
  final List<PaymentRecord> payments;
  final List<ExpenseRecord> expenses;
  final List<RefundRecord> refunds;
  final List<CashMovement> cashMovements;
  final bool canUseOnlineAI;
  final bool canSeeFullData;
  final double periodRevenue;
  final double netProfit;
  final String selectedPeriod;

  @override
  State<LocalAssistantCard> createState() => _LocalAssistantCardState();
}

class _LocalAssistantCardState extends State<LocalAssistantCard> {
  final question = TextEditingController();
  String? answer;
  String? answeredQuestion;
  String? answerNotice;
  bool onlineModeEnabled = false;
  bool onlineAnswering = false;
  bool answerCameFromOnline = false;

  @override
  void dispose() {
    question.dispose();
    super.dispose();
  }

  Future<void> _ask(String value) async {
    if (onlineAnswering) return;
    question.text = value;
    final query = _normalizeAssistantQuery(value);
    if (query.isEmpty) return;

    final words = query.split(' ').toSet();
    bool hasAny(Set<String> terms) => terms.any(words.contains);
    final asksBestSeller =
        query.contains('plus vendu') ||
        query.contains('mieux vendu') ||
        query.contains('se vend le mieux') ||
        query.contains('meilleur produit') ||
        query.contains('produit qui marche') ||
        query.contains('best seller') ||
        query.contains('top produit') ||
        query.contains('top selling') ||
        query.contains('best selling');
    String response;
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final periodStart = switch (widget.selectedPeriod) {
      'Aujourd’hui' => todayStart,
      'Cette semaine' => todayStart.subtract(Duration(days: now.weekday - 1)),
      'Ce mois' => DateTime(now.year, now.month, 1),
      'Cette année' => DateTime(now.year, 1, 1),
      _ => DateTime(1),
    };
    // The normalizer turns French apostrophes into spaces, so accept both
    // spellings for « aujourd'hui » and its normalized form.
    final asksToday =
        hasAny({'aujourdhui', 'today', 'cejour'}) ||
        query.contains('aujourd hui');
    final asksSale = hasAny({
      'vente',
      'ventes',
      'vendu',
      'vendue',
      'vendre',
      'vend',
      'recette',
      'recettes',
      'revenue',
      'sales',
      'sale',
    });
    final knownProducts = <Product>[
      ...widget.products,
      ...widget.allSales.map((sale) => sale.product),
    ];
    final matchingProduct = knownProducts.where((product) {
      final productName = _normalizeAssistantQuery(product.name);
      return productName.length > 1 &&
          (query.contains(productName) ||
              productName
                  .split(' ')
                  .where((part) => part.length >= 3)
                  .any((part) => words.contains(part)));
    }).toList()..sort((a, b) => b.name.length.compareTo(a.name.length));
    final latestSaleQuestion =
        asksSale && hasAny({'dernier', 'derniere', 'recent', 'last', 'latest'});

    if (latestSaleQuestion) {
      final latest = [...widget.allSales]
        ..sort((a, b) => b.date.compareTo(a.date));
      response = latest.isEmpty
          ? _tr(
              'Aucune vente n’est encore enregistrée.',
              'No sales have been recorded yet.',
            )
          : _tr(
              'La dernière vente est ${latest.first.product.name} (${_money(latest.first.total)}), le ${_dateTime(latest.first.date)}.',
              'The latest sale was ${latest.first.product.name} (${_money(latest.first.total)}) on ${_dateTime(latest.first.date)}.',
            );
    } else if (asksToday && asksSale) {
      final todaySales = widget.allSales
          .where(
            (sale) =>
                !sale.date.isBefore(todayStart) &&
                sale.date.isBefore(todayStart.add(const Duration(days: 1))),
          )
          .toList();
      final selectedSales = matchingProduct.isEmpty
          ? todaySales
          : todaySales
                .where(
                  (sale) =>
                      _normalizeAssistantQuery(sale.product.name) ==
                      _normalizeAssistantQuery(matchingProduct.first.name),
                )
                .toList();
      final count = selectedSales
          .map((sale) => sale.receiptNumber)
          .toSet()
          .length;
      final quantitySold = selectedSales.fold<double>(
        0,
        (sum, sale) => sum + sale.stockQuantity,
      );
      final revenue = selectedSales.fold<double>(
        0,
        (sum, sale) => sum + sale.total,
      );
      final label = matchingProduct.isEmpty
          ? 'la boutique'
          : matchingProduct.first.name;
      response = selectedSales.isEmpty
          ? _tr(
              'Aucune vente${matchingProduct.isEmpty ? '' : ' de $label'} n’est enregistrée aujourd’hui.',
              'No sales${matchingProduct.isEmpty ? '' : ' of $label'} are recorded today.',
            )
          : _tr(
              'Aujourd’hui, $label : $count vente(s), ${_quantity(quantitySold)} unité(s) vendue(s), pour ${_money(revenue)}.',
              'Today, $label: $count sale(s), ${_quantity(quantitySold)} unit(s) sold, totaling ${_money(revenue)}.',
            );
    } else if (asksSale && matchingProduct.isNotEmpty) {
      final productName = _normalizeAssistantQuery(matchingProduct.first.name);
      final selectedSales = widget.allSales.where((sale) {
        final normalizedName = _normalizeAssistantQuery(sale.product.name);
        final isProductMatch =
            normalizedName == productName ||
            productName.contains(normalizedName) ||
            normalizedName.contains(productName);
        return isProductMatch &&
            !sale.date.isBefore(periodStart) &&
            !sale.date.isAfter(now);
      }).toList();
      final count = selectedSales
          .map((sale) => sale.receiptNumber)
          .toSet()
          .length;
      final quantitySold = selectedSales.fold<double>(
        0,
        (sum, sale) => sum + sale.stockQuantity,
      );
      final revenue = selectedSales.fold<double>(
        0,
        (sum, sale) => sum + sale.total,
      );
      response = selectedSales.isEmpty
          ? _tr(
              'Je ne trouve aucune vente de ${matchingProduct.first.name} sur ${_periodLabel(widget.selectedPeriod).toLowerCase()}.',
              'I found no sales of ${matchingProduct.first.name} for ${_periodLabel(widget.selectedPeriod).toLowerCase()}.',
            )
          : _tr(
              'Sur ${_periodLabel(widget.selectedPeriod).toLowerCase()}, ${matchingProduct.first.name} : $count vente(s), ${_quantity(quantitySold)} ${_unitLabel(matchingProduct.first.unit)} vendue(s), pour ${_money(revenue)}.',
              'For ${_periodLabel(widget.selectedPeriod).toLowerCase()}, ${matchingProduct.first.name}: $count sale(s), ${_quantity(quantitySold)} ${_unitLabel(matchingProduct.first.unit)} sold, totaling ${_money(revenue)}.',
            );
    } else if (asksToday &&
        hasAny({
          'achat',
          'achats',
          'approvisionnement',
          'approvisionne',
          'approvisionnee',
          'commande',
          'commander',
          'purchase',
          'purchases',
        })) {
      final todayPurchases = widget.purchases
          .where(
            (purchase) =>
                !purchase.date.isBefore(todayStart) &&
                purchase.date.isBefore(todayStart.add(const Duration(days: 1))),
          )
          .toList();
      final total = todayPurchases.fold<double>(
        0,
        (sum, item) => sum + item.totalCost,
      );
      response = !widget.canSeeFullData
          ? _tr(
              'Les détails des achats ne sont pas partagés avec ce compte employé.',
              'Purchase details are not shared with this employee account.',
            )
          : todayPurchases.isEmpty
          ? _tr(
              'Aucun approvisionnement n’est enregistré aujourd’hui.',
              'No purchases are recorded today.',
            )
          : _tr(
              'Aujourd’hui, ${todayPurchases.length} approvisionnement(s) pour ${_money(total)} : ${todayPurchases.take(5).map((item) => '${item.product.name} (${_quantity(item.quantity)} ${_unitLabel(item.product.unit)})').join(', ')}.',
              'Today, ${todayPurchases.length} purchase(s) totaling ${_money(total)}: ${todayPurchases.take(5).map((item) => '${item.product.name} (${_quantity(item.quantity)} ${_unitLabel(item.product.unit)})').join(', ')}.',
            );
    } else if (asksToday &&
        hasAny({'depense', 'depenses', 'depensee', 'expense', 'expenses'})) {
      final todayExpenses = widget.expenses
          .where(
            (expense) =>
                !expense.date.isBefore(todayStart) &&
                expense.date.isBefore(todayStart.add(const Duration(days: 1))),
          )
          .toList();
      final total = todayExpenses.fold<double>(
        0,
        (sum, item) => sum + item.amount,
      );
      response = !widget.canSeeFullData
          ? _tr(
              'Les détails des dépenses ne sont pas partagés avec ce compte employé.',
              'Expense details are not shared with this employee account.',
            )
          : todayExpenses.isEmpty
          ? _tr(
              'Aucune dépense n’est enregistrée aujourd’hui.',
              'No expenses are recorded today.',
            )
          : _tr(
              'Aujourd’hui, ${todayExpenses.length} dépense(s) pour ${_money(total)}. Catégories : ${todayExpenses.map((item) => item.category).toSet().join(', ')}.',
              'Today, ${todayExpenses.length} expense(s) totaling ${_money(total)}. Categories: ${todayExpenses.map((item) => item.category).toSet().join(', ')}.',
            );
    } else if (hasAny({
      'achat',
      'achats',
      'approvisionnement',
      'fournisseur',
      'purchase',
      'purchases',
    })) {
      final selectedPurchases = widget.purchases
          .where((item) => !item.date.isBefore(periodStart))
          .toList();
      final total = selectedPurchases.fold<double>(
        0,
        (sum, item) => sum + item.totalCost,
      );
      response = !widget.canSeeFullData
          ? _tr(
              'Les détails des achats ne sont pas partagés avec ce compte employé.',
              'Purchase details are not shared with this employee account.',
            )
          : selectedPurchases.isEmpty
          ? _tr(
              'Aucun achat n’est enregistré sur ${_periodLabel(widget.selectedPeriod).toLowerCase()}.',
              'No purchases are recorded for ${_periodLabel(widget.selectedPeriod).toLowerCase()}.',
            )
          : _tr(
              'Sur ${_periodLabel(widget.selectedPeriod).toLowerCase()}, ${selectedPurchases.length} achat(s) représentent ${_money(total)}. Produits : ${selectedPurchases.take(5).map((item) => '${item.product.name} (${_quantity(item.quantity)} ${_unitLabel(item.product.unit)})').join(', ')}.',
              'For ${_periodLabel(widget.selectedPeriod).toLowerCase()}, ${selectedPurchases.length} purchase(s) total ${_money(total)}. Products: ${selectedPurchases.take(5).map((item) => '${item.product.name} (${_quantity(item.quantity)} ${_unitLabel(item.product.unit)})').join(', ')}.',
            );
    } else if (hasAny({'depense', 'depenses', 'expense', 'expenses'})) {
      final selectedExpenses = widget.expenses
          .where((item) => !item.date.isBefore(periodStart))
          .toList();
      final total = selectedExpenses.fold<double>(
        0,
        (sum, item) => sum + item.amount,
      );
      response = !widget.canSeeFullData
          ? _tr(
              'Les détails des dépenses ne sont pas partagés avec ce compte employé.',
              'Expense details are not shared with this employee account.',
            )
          : selectedExpenses.isEmpty
          ? _tr(
              'Aucune dépense n’est enregistrée sur ${_periodLabel(widget.selectedPeriod).toLowerCase()}.',
              'No expenses are recorded for ${_periodLabel(widget.selectedPeriod).toLowerCase()}.',
            )
          : _tr(
              'Sur ${_periodLabel(widget.selectedPeriod).toLowerCase()}, ${selectedExpenses.length} dépense(s) totalisent ${_money(total)}. Catégories : ${selectedExpenses.map((item) => item.category).toSet().join(', ')}.',
              'For ${_periodLabel(widget.selectedPeriod).toLowerCase()}, ${selectedExpenses.length} expense(s) total ${_money(total)}. Categories: ${selectedExpenses.map((item) => item.category).toSet().join(', ')}.',
            );
    } else if (hasAny({
      'paiement',
      'paiements',
      'encaissement',
      'encaissements',
      'payment',
      'payments',
    })) {
      final selectedPayments = widget.payments
          .where((item) => !item.date.isBefore(periodStart))
          .toList();
      final total = selectedPayments.fold<double>(
        0,
        (sum, item) => sum + item.amount,
      );
      response = selectedPayments.isEmpty
          ? _tr(
              'Aucun paiement client n’est enregistré sur ${_periodLabel(widget.selectedPeriod).toLowerCase()}.',
              'No customer payments are recorded for ${_periodLabel(widget.selectedPeriod).toLowerCase()}.',
            )
          : _tr(
              'Sur ${_periodLabel(widget.selectedPeriod).toLowerCase()}, ${selectedPayments.length} paiement(s) client totalisent ${_money(total)}.',
              'For ${_periodLabel(widget.selectedPeriod).toLowerCase()}, ${selectedPayments.length} customer payment(s) total ${_money(total)}.',
            );
    } else if (hasAny({
      'retour',
      'retours',
      'remboursement',
      'remboursements',
      'refund',
    })) {
      final selectedRefunds = widget.refunds
          .where((item) => !item.date.isBefore(periodStart))
          .toList();
      final total = selectedRefunds.fold<double>(
        0,
        (sum, item) => sum + item.value,
      );
      response = !widget.canSeeFullData
          ? _tr(
              'Les informations sur les retours ne sont pas partagées avec ce compte employé.',
              'Return details are not shared with this employee account.',
            )
          : selectedRefunds.isEmpty
          ? _tr(
              'Aucun retour ou remboursement n’est enregistré sur ${_periodLabel(widget.selectedPeriod).toLowerCase()}.',
              'No returns or refunds are recorded for ${_periodLabel(widget.selectedPeriod).toLowerCase()}.',
            )
          : _tr(
              'Sur ${_periodLabel(widget.selectedPeriod).toLowerCase()}, ${selectedRefunds.length} retour(s) représentent ${_money(total)} de marchandises, dont ${_money(selectedRefunds.fold<double>(0, (sum, item) => sum + item.cashRefund))} remboursés en espèces.',
              'For ${_periodLabel(widget.selectedPeriod).toLowerCase()}, ${selectedRefunds.length} return(s) total ${_money(total)} of goods, with ${_money(selectedRefunds.fold<double>(0, (sum, item) => sum + item.cashRefund))} refunded in cash.',
            );
    } else if (asksBestSeller) {
      if (widget.periodSales.isEmpty) {
        response = _tr(
          'Je n’ai pas encore de vente sur la période choisie.',
          'There are no sales in the selected period yet.',
        );
      } else {
        final quantities = <String, double>{};
        final labels = <String, String>{};
        final units = <String, String>{};
        for (final sale in widget.periodSales) {
          final key =
              '${sale.product.name.trim().toLowerCase()}|${sale.product.category.trim().toLowerCase()}';
          quantities.update(
            key,
            (current) => current + sale.stockQuantity,
            ifAbsent: () => sale.stockQuantity,
          );
          labels[key] = sale.product.name;
          units[key] = sale.product.unit;
        }
        final ranked = quantities.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        final periodLabel = _periodLabel(widget.selectedPeriod).toLowerCase();
        response = _tr(
          'Sur $periodLabel, ${labels[ranked.first.key]} est le plus vendu : ${_quantity(ranked.first.value)} ${_unitLabel(units[ranked.first.key]!)}.',
          'For $periodLabel, ${labels[ranked.first.key]} is your top seller: ${_quantity(ranked.first.value)} ${_unitLabel(units[ranked.first.key]!)}.',
        );
      }
    } else if (hasAny({
      'acheter',
      'achats',
      'commande',
      'commander',
      'approvisionnement',
      'reapprovisionnement',
      'reapprovisionner',
      'reappro',
      'racheter',
    })) {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final recentStart = today.subtract(const Duration(days: 6));
      final recentSales = widget.allSales.where(
        (sale) => !sale.date.isBefore(recentStart) && !sale.date.isAfter(now),
      );
      final unitsSold = <String, double>{};
      for (final sale in recentSales) {
        final key =
            '${sale.product.name.trim().toLowerCase()}|${sale.product.category.trim().toLowerCase()}';
        unitsSold.update(
          key,
          (quantity) => quantity + sale.stockQuantity,
          ifAbsent: () => sale.stockQuantity,
        );
      }
      if (unitsSold.isEmpty) {
        response = _tr(
          'Je n’ai pas assez de ventes récentes pour estimer les achats. Enregistre quelques ventes, puis réessaie.',
          'There are not enough recent sales to estimate purchases. Record a few sales and try again.',
        );
      } else {
        final suggestions =
            <
              ({Product product, double quantity, double daysLeft, double cost})
            >[];
        for (final product in widget.products) {
          final key =
              '${product.name.trim().toLowerCase()}|${product.category.trim().toLowerCase()}';
          final dailyRate = (unitsSold[key] ?? 0) / 7;
          if (dailyRate <= 0) continue;
          final daysLeft = product.quantity / dailyRate;
          final quantityToBuy = max(
            0.0,
            (dailyRate * 14 - product.quantity).ceilToDouble(),
          );
          if (quantityToBuy > 0) {
            suggestions.add((
              product: product,
              quantity: quantityToBuy,
              daysLeft: daysLeft,
              cost: quantityToBuy * product.purchasePrice,
            ));
          }
        }
        suggestions.sort((a, b) => a.daysLeft.compareTo(b.daysLeft));
        if (suggestions.isEmpty) {
          response = _tr(
            'Au rythme des ventes récentes, le stock actuel couvre environ 14 jours pour les produits vendus. Aucun achat urgent estimé.',
            'At the recent sales rate, current stock covers about 14 days for products sold. No urgent restock is estimated.',
          );
        } else {
          final visible = suggestions.take(5).toList();
          final estimatedTotal = visible.fold<double>(
            0,
            (sum, item) => sum + item.cost,
          );
          final itemList = visible
              .map(
                (item) =>
                    '${item.product.name} : ${_quantity(item.quantity)} ${_unitLabel(item.product.unit)} (${_money(item.cost)})',
              )
              .join(', ');
          response = _tr(
            'Pour viser 14 jours de stock, les achats à prévoir selon les 7 derniers jours sont : $itemList. Estimation pour ces ${visible.length} produit(s) : ${_money(estimatedTotal)}.',
            'To target 14 days of stock, based on the last 7 days consider buying: $itemList. Estimated cost for these ${visible.length} product(s): ${_money(estimatedTotal)}.',
          );
        }
      }
    } else if (hasAny({
      'doit',
      'doivent',
      'dette',
      'dettes',
      'credit',
      'creance',
      'payer',
      'impaye',
      'owe',
      'owes',
      'owed',
      'debt',
      'debts',
      'unpaid',
    })) {
      final balances = <String, double>{};
      final customerLabels = <String, String>{};
      for (final sale in widget.allSales.where((sale) => sale.balance > 0)) {
        final name = sale.customerName.trim().isEmpty
            ? _tr('Client sans nom', 'Unnamed customer')
            : sale.customerName.trim();
        final key = name.toLowerCase();
        balances.update(
          key,
          (current) => current + sale.balance,
          ifAbsent: () => sale.balance,
        );
        customerLabels[key] = name;
      }
      final ranked = balances.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      response = ranked.isEmpty
          ? _tr(
              'Aucun crédit client n’est en attente.',
              'No customer credit is outstanding.',
            )
          : _tr(
              'Total à encaisser : ${_money(ranked.fold<double>(0, (sum, item) => sum + item.value))}. Les principaux soldes : ${ranked.take(4).map((item) => '${customerLabels[item.key]} (${_money(item.value)})').join(', ')}.',
              'Total still owed: ${_money(ranked.fold<double>(0, (sum, item) => sum + item.value))}. Largest balances: ${ranked.take(4).map((item) => '${customerLabels[item.key]} (${_money(item.value)})').join(', ')}.',
            );
    } else if (hasAny({
      'stock',
      'rupture',
      'manque',
      'reapprovisionner',
      'reappro',
      'bas',
    })) {
      final lowStock =
          widget.products
              .where((product) => product.quantity <= product.lowStockLimit)
              .toList()
            ..sort((a, b) => a.quantity.compareTo(b.quantity));
      response = lowStock.isEmpty
          ? _tr(
              'Aucun produit n’est actuellement sous son seuil de stock bas.',
              'No products are currently below their low-stock threshold.',
            )
          : _tr(
              '${lowStock.length} produit(s) à vérifier : ${lowStock.take(5).map((product) => '${product.name} (${_quantity(product.quantity)} ${_unitLabel(product.unit)} restants)').join(', ')}.',
              '${lowStock.length} product(s) to check: ${lowStock.take(5).map((product) => '${product.name} (${_quantity(product.quantity)} ${_unitLabel(product.unit)} left)').join(', ')}.',
            );
    } else if (hasAny({'benefice', 'profit', 'marge', 'gagne'})) {
      response = widget.canSeeFullData
          ? _tr(
              'Le bénéfice net estimé sur ${_periodLabel(widget.selectedPeriod).toLowerCase()} est de ${_money(widget.netProfit)}.',
              'Estimated net profit for ${_periodLabel(widget.selectedPeriod).toLowerCase()} is ${_money(widget.netProfit)}.',
            )
          : _tr(
              'La marge et le bénéfice ne sont pas partagés avec ce compte employé.',
              'Profit and margin details are not shared with this employee account.',
            );
    } else if (hasAny({
          'vente',
          'ventes',
          'vendu',
          'recette',
          'recettes',
          'revenu',
          'revenus',
          'chiffre',
          'affaire',
          'affaires',
          'resume',
          'bilan',
          'sales',
          'sale',
          'revenue',
          'income',
          'turnover',
        }) ||
        query.contains('combien')) {
      response = _tr(
        'Sur ${_periodLabel(widget.selectedPeriod).toLowerCase()}, ${widget.periodSales.length} vente(s) ont généré ${_money(widget.periodRevenue)} de chiffre d’affaires.',
        'For ${_periodLabel(widget.selectedPeriod).toLowerCase()}, ${widget.periodSales.length} sale(s) generated ${_money(widget.periodRevenue)} in revenue.',
      );
    } else {
      response = _tr(
        'Je peux répondre sur vos produits les plus vendus, les stocks bas, les crédits clients, le chiffre d’affaires ou le bénéfice. Essayez une suggestion ci-dessous.',
        'I can answer about top-selling products, low stock, customer credit, revenue, or profit. Try one of the suggestions below.',
      );
    }

    final shouldTryOnline =
        widget.canUseOnlineAI &&
        onlineModeEnabled &&
        widget.businessId != null &&
        widget.businessId!.isNotEmpty;
    setState(() {
      answeredQuestion = value;
      answer = response;
      answerCameFromOnline = false;
      onlineAnswering = shouldTryOnline;
      answerNotice = shouldTryOnline
          ? _tr(
              'Réponse locale affichée pendant la recherche en ligne…',
              'Showing the local answer while checking online…',
            )
          : _tr(
              'Réponse locale calculée sur cet appareil.',
              'Answer calculated locally on this device.',
            );
    });

    if (!widget.canUseOnlineAI || !onlineModeEnabled) return;
    if (widget.businessId == null || widget.businessId!.isEmpty) {
      setState(() {
        answerNotice = _tr(
          'Le commerce doit être synchronisé pour utiliser l’IA en ligne. La réponse locale reste disponible.',
          'The business must be synced to use online AI. The local answer is still available.',
        );
      });
      return;
    }

    try {
      final result = await Supabase.instance.client.functions.invoke(
        'bizgestion-ai',
        body: {
          'business_id': widget.businessId,
          'question': value,
          'currency_code': _activeCurrencyCode,
        },
      );
      final data = result.data;
      final onlineResponse = data is Map ? data['answer'] : null;
      if (result.status < 200 ||
          result.status >= 300 ||
          onlineResponse is! String ||
          onlineResponse.trim().isEmpty) {
        throw StateError('Réponse IA indisponible.');
      }
      if (!mounted) return;
      setState(() {
        answer = onlineResponse.trim();
        answerCameFromOnline = true;
        onlineAnswering = false;
        answerNotice = _tr(
          'Réponse de l’IA en ligne.',
          'Answer from online AI.',
        );
      });
    } catch (error) {
      if (!mounted) return;
      final errorText = error.toString().toLowerCase();
      final quotaReached =
          errorText.contains('429') ||
          errorText.contains('quota_ia_journaliere_atteinte');
      debugPrint('Online BizGestion AI request failed: $error');
      setState(() {
        answerCameFromOnline = false;
        onlineAnswering = false;
        answerNotice = quotaReached
            ? _tr(
                'Quota de questions IA atteint pour aujourd’hui; la réponse locale est conservée.',
                'The AI question quota for today has been reached; the local answer is kept.',
              )
            : _tr(
                'IA en ligne indisponible ou non configurée; la réponse locale est conservée.',
                'Online AI is unavailable or not configured; the local answer is kept.',
              );
      });
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    color: Colors.white,
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: const BorderSide(color: Color(0xFFE8EDEF)),
    ),
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.chat_bubble_outline_rounded, color: teal),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  _tr('Demandez à BizGestion', 'Ask BizGestion'),
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                    color: ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            _tr(
              'Posez une question en français. Le mode local fonctionne hors ligne; le mode en ligne comprend des demandes plus libres.',
              'Ask in plain language. Local mode works offline; online mode understands more open-ended questions.',
            ),
            style: const TextStyle(color: Colors.black54),
          ),
          if (widget.canUseOnlineAI)
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: onlineModeEnabled,
              onChanged: onlineAnswering
                  ? null
                  : (enabled) => setState(() => onlineModeEnabled = enabled),
              title: Text(
                _tr('Activer l’IA en ligne', 'Enable online AI'),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                _tr(
                  'Réservée au propriétaire. Vos questions et un résumé anonymisé du commerce sont envoyés à OpenAI. Limite : 5 questions par jour en gratuit; environ 1 695 par mois en Commerce et 2 825 en Entreprise.',
                  'Owner only. Your questions and an anonymized business summary are sent to OpenAI. Limit: 5 questions per day on Free; about 1,695/month on Commerce and 2,825 on Enterprise.',
                ),
              ),
            )
          else
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.lock_outline, color: teal),
              title: Text(
                _tr(
                  'Mode en ligne réservé au propriétaire',
                  'Online mode is owner only',
                ),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                _tr(
                  'Vous pouvez utiliser l’assistant local hors ligne. Seul le propriétaire peut envoyer des questions à l’IA en ligne.',
                  'You can use the local assistant offline. Only the owner can send questions to online AI.',
                ),
              ),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: question,
                  enabled: !onlineAnswering,
                  maxLength: 500,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (value) => _ask(value),
                  decoration: InputDecoration(
                    hintText: _tr(
                      'Ex. : Qui me doit de l’argent ?',
                      'E.g. Who owes me money?',
                    ),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                tooltip: _tr('Répondre', 'Ask'),
                onPressed: onlineAnswering ? null : () => _ask(question.text),
                icon: onlineAnswering
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.arrow_upward_rounded),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _suggestion(_tr('Produit le plus vendu', 'Top-selling product')),
              _suggestion(_tr('Qui me doit ?', 'Who owes me?')),
              _suggestion(_tr('Stock à vérifier', 'Stock to check')),
              _suggestion(
                _tr('Que réapprovisionner ?', 'What should I restock?'),
              ),
              _suggestion(_tr('Mes ventes', 'My sales')),
            ],
          ),
          if (answer != null) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF4F8F7),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    answeredQuestion ?? '',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: teal,
                    ),
                  ),
                  const SizedBox(height: 5),
                  if (answerNotice != null) ...[
                    Row(
                      children: [
                        if (onlineAnswering)
                          const SizedBox.square(
                            dimension: 13,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else
                          Icon(
                            answerCameFromOnline
                                ? Icons.cloud_done_outlined
                                : Icons.offline_bolt_outlined,
                            size: 15,
                            color: teal,
                          ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            answerNotice!,
                            style: const TextStyle(
                              color: Colors.black54,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                  ],
                  Text(answer!),
                ],
              ),
            ),
          ],
        ],
      ),
    ),
  );

  Widget _suggestion(String label) => ActionChip(
    label: Text(label),
    onPressed: onlineAnswering ? null : () => _ask(label),
    visualDensity: VisualDensity.compact,
  );
}

class DashboardContent extends StatelessWidget {
  const DashboardContent({
    super.key,
    required this.businessId,
    required this.isDesktop,
    required this.currentPage,
    required this.selectedPeriod,
    required this.onPeriodChanged,
    required this.products,
    required this.purchases,
    required this.payments,
    required this.refunds,
    required this.cashMovements,
    required this.canUseOnlineAI,
    required this.canSeeFullData,
    required this.canManageData,
    required this.onAddProduct,
    required this.sales,
    required this.expenses,
    required this.onOpenStock,
    required this.onOpenPurchases,
    required this.onOpenSales,
    required this.onOpenCustomers,
    required this.onOpenExpenses,
    required this.onExportBackup,
  });

  final String? businessId;
  final bool isDesktop;
  final String currentPage;
  final String selectedPeriod;
  final ValueChanged<String> onPeriodChanged;
  final List<Product> products;
  final List<PurchaseRecord> purchases;
  final List<PaymentRecord> payments;
  final List<RefundRecord> refunds;
  final List<CashMovement> cashMovements;
  final bool canUseOnlineAI;
  final bool canSeeFullData;
  final bool canManageData;
  final VoidCallback onAddProduct;
  final List<SaleRecord> sales;
  final List<ExpenseRecord> expenses;
  final VoidCallback onOpenStock;
  final VoidCallback onOpenPurchases;
  final VoidCallback onOpenSales;
  final VoidCallback onOpenCustomers;
  final VoidCallback onOpenExpenses;
  final VoidCallback onExportBackup;

  DateTime _periodStart() {
    final now = DateTime.now();
    return switch (selectedPeriod) {
      'Aujourd’hui' => DateTime(now.year, now.month, now.day),
      'Cette semaine' => DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(Duration(days: now.weekday - 1)),
      'Ce mois' => DateTime(now.year, now.month, 1),
      'Cette année' => DateTime(now.year, 1, 1),
      _ => DateTime(1),
    };
  }

  bool _isInSelectedPeriod(DateTime date) =>
      selectedPeriod == 'Tout' || !date.isBefore(_periodStart());

  List<SaleRecord> get periodSales =>
      sales.where((sale) => _isInSelectedPeriod(sale.date)).toList();
  List<PurchaseRecord> get periodPurchases => purchases
      .where((purchase) => _isInSelectedPeriod(purchase.date))
      .toList();
  List<ExpenseRecord> get periodExpenses =>
      expenses.where((expense) => _isInSelectedPeriod(expense.date)).toList();

  double get periodRevenue =>
      periodSales.fold(0.0, (sum, sale) => sum + sale.total);
  double get totalCredit => sales.fold(0.0, (sum, sale) => sum + sale.balance);
  double get totalPurchaseCost =>
      periodPurchases.fold(0.0, (sum, purchase) => sum + purchase.totalCost);
  double get periodExpenseTotal =>
      periodExpenses.fold(0.0, (sum, expense) => sum + expense.amount);
  double get averageTicket =>
      periodSales.isEmpty ? 0 : periodRevenue / periodSales.length;
  double get netProfit =>
      periodSales.fold(0.0, (sum, sale) => sum + sale.grossProfit) -
      periodExpenses.fold(0.0, (sum, expense) => sum + expense.amount);
  double get stockValue => products.fold(
    0.0,
    (sum, product) => sum + product.quantity * product.purchasePrice,
  );
  double get potentialStockProfit => products.fold(
    0.0,
    (sum, product) =>
        sum +
        product.quantity *
            (product.retailPrice * product.retailUnitsPerStockUnit -
                product.purchasePrice),
  );
  List<Product> get lowStockProducts =>
      products
          .where((product) => product.quantity <= product.lowStockLimit)
          .toList()
        ..sort((a, b) => a.quantity.compareTo(b.quantity));
  List<Product> get expiringProducts =>
      products
          .where(
            (product) =>
                product.quantity > 0 &&
                (_daysUntilExpiry(product) ?? 9999) <= 30,
          )
          .toList()
        ..sort((a, b) => _daysUntilExpiry(a)!.compareTo(_daysUntilExpiry(b)!));
  List<Product> get expiredProducts => expiringProducts
      .where((product) => _daysUntilExpiry(product)! < 0)
      .toList();
  List<Product> get productsExpiringSoon => expiringProducts
      .where((product) => _daysUntilExpiry(product)! >= 0)
      .toList();
  int get indebtedCustomerCount => sales
      .where((sale) => sale.balance > 0)
      .map((sale) => sale.customerName.trim().toLowerCase())
      .where((name) => name.isNotEmpty)
      .toSet()
      .length;
  List<SaleRecord> get overdueSales {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return sales.where((sale) {
      final dueDate = sale.dueDate;
      return sale.balance > 0 &&
          dueDate != null &&
          DateTime(dueDate.year, dueDate.month, dueDate.day).isBefore(today);
    }).toList();
  }

  int get overdueCustomerCount => overdueSales
      .map((sale) => sale.customerName.trim().toLowerCase())
      .where((name) => name.isNotEmpty)
      .toSet()
      .length;
  double get overdueBalance =>
      overdueSales.fold(0.0, (sum, sale) => sum + sale.balance);
  int get pendingPickupCount => sales
      .where((sale) => sale.pickupStatus == 'À retirer')
      .map((sale) => sale.receiptNumber)
      .toSet()
      .length;

  List<_BusinessInsight> get businessInsights {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final recentStart = today.subtract(const Duration(days: 6));
    final previousStart = recentStart.subtract(const Duration(days: 7));
    final recentSales = sales
        .where(
          (sale) => !sale.date.isBefore(recentStart) && !sale.date.isAfter(now),
        )
        .toList();
    final previousSales = sales
        .where(
          (sale) =>
              !sale.date.isBefore(previousStart) &&
              sale.date.isBefore(recentStart),
        )
        .toList();
    final insights = <_BusinessInsight>[];

    if (recentSales.isNotEmpty) {
      final soldByProduct = <String, double>{};
      final productLabels = <String, String>{};
      for (final sale in recentSales) {
        final key =
            '${sale.product.name.trim().toLowerCase()}|${sale.product.category.trim().toLowerCase()}';
        soldByProduct.update(
          key,
          (quantity) => quantity + sale.stockQuantity,
          ifAbsent: () => sale.stockQuantity,
        );
        productLabels[key] = sale.product.name;
      }
      final bestSeller = soldByProduct.entries.reduce(
        (best, item) => item.value > best.value ? item : best,
      );
      final bestName = productLabels[bestSeller.key]!;
      Product? bestProduct;
      for (final product in products) {
        if (product.name.trim().toLowerCase() ==
            bestName.trim().toLowerCase()) {
          bestProduct = product;
          break;
        }
      }
      insights.add(
        _BusinessInsight(
          icon: Icons.local_fire_department_outlined,
          title: _tr(
            'Votre produit le plus vendu',
            'Your best-selling product',
          ),
          detail: _tr(
            '$bestName est en tête sur les 7 derniers jours (${_quantity(bestSeller.value)} ${bestProduct?.unit ?? ''}).',
            '$bestName leads over the last 7 days (${_quantity(bestSeller.value)} ${bestProduct?.unit ?? ''}).',
          ),
          color: const Color(0xFFD88931),
        ),
      );

      final unitsSoldByKey = <String, double>{};
      for (final sale in recentSales) {
        final key =
            '${sale.product.name.trim().toLowerCase()}|${sale.product.category.trim().toLowerCase()}';
        unitsSoldByKey.update(
          key,
          (quantity) => quantity + sale.stockQuantity,
          ifAbsent: () => sale.stockQuantity,
        );
      }
      final fastMoving =
          products
              .where((product) => product.quantity > 0)
              .map((product) {
                final key =
                    '${product.name.trim().toLowerCase()}|${product.category.trim().toLowerCase()}';
                final dailyRate = (unitsSoldByKey[key] ?? 0) / 7;
                return (
                  product: product,
                  daysLeft: dailyRate == 0
                      ? double.infinity
                      : product.quantity / dailyRate,
                  suggestedOrder: dailyRate == 0
                      ? 0.0
                      : max(
                          0.0,
                          (dailyRate * 14 - product.quantity).ceilToDouble(),
                        ),
                );
              })
              .where((item) => item.daysLeft <= 14)
              .toList()
            ..sort((a, b) => a.daysLeft.compareTo(b.daysLeft));
      if (fastMoving.isNotEmpty) {
        final item = fastMoving.first;
        final days = item.daysLeft.ceil().clamp(1, 14);
        final dayUnit = _activeLanguageCode == 'en'
            ? (days == 1 ? 'day' : 'days')
            : (days == 1 ? 'jour' : 'jours');
        insights.add(
          _BusinessInsight(
            icon: Icons.inventory_2_outlined,
            title: _tr(
              'Réapprovisionnement à prévoir',
              'Restock recommendation',
            ),
            detail: _tr(
              'Au rythme des 7 derniers jours, ${item.product.name} pourrait manquer dans environ $days $dayUnit. Pour couvrir 14 jours, prévoyez environ ${_quantity(item.suggestedOrder)} ${_unitLabel(item.product.unit)} de plus.',
              'At the pace of the last 7 days, ${item.product.name} may run out in about $days $dayUnit. To cover 14 days, consider ordering about ${_quantity(item.suggestedOrder)} more ${_unitLabel(item.product.unit)}.',
            ),
            color: const Color(0xFFB84A52),
          ),
        );
      }
    }

    final belowCostProducts = products.where((product) {
      if (product.retailUnitsPerStockUnit <= 0) return false;
      final purchaseCostPerUnit =
          product.purchasePrice / product.retailUnitsPerStockUnit;
      return product.retailPrice < purchaseCostPerUnit;
    }).toList();
    if (belowCostProducts.isNotEmpty) {
      final examples = belowCostProducts
          .take(3)
          .map((product) => product.name)
          .join(' • ');
      insights.add(
        _BusinessInsight(
          icon: Icons.price_change_outlined,
          title: _tr('Prix de vente à vérifier', 'Review selling price'),
          detail: _tr(
            '${belowCostProducts.length} produit(s) semblent vendus sous leur coût d’achat unitaire : $examples. Vérifiez le prix ou le coût enregistré.',
            '${belowCostProducts.length} product(s) appear priced below unit purchase cost: $examples. Check the selling price or recorded cost.',
          ),
          color: const Color(0xFFB3261E),
        ),
      );
    }

    final recentRevenue = recentSales.fold<double>(
      0,
      (sum, sale) => sum + sale.total,
    );
    final previousRevenue = previousSales.fold<double>(
      0,
      (sum, sale) => sum + sale.total,
    );
    if (previousRevenue > 0) {
      final change = recentRevenue - previousRevenue;
      final improved = change >= 0;
      insights.add(
        _BusinessInsight(
          icon: improved
              ? Icons.trending_up_rounded
              : Icons.trending_down_rounded,
          title: _tr('Évolution des ventes', 'Sales trend'),
          detail: _tr(
            'Votre chiffre d’affaires des 7 derniers jours est de ${_money(recentRevenue)}, soit ${_money(change.abs())} ${improved ? 'de plus' : 'de moins'} que les ${_money(previousRevenue)} des 7 jours précédents.',
            'Revenue over the last 7 days is ${_money(recentRevenue)}, ${improved ? 'up' : 'down'} ${_money(change.abs())} from ${_money(previousRevenue)} in the previous 7 days.',
          ),
          color: improved ? const Color(0xFF27966F) : const Color(0xFFB84A52),
        ),
      );
    }

    return insights.take(3).toList();
  }

  List<_ProfitCostBucket> _overviewBuckets() {
    final now = DateTime.now();
    final monthLabels = _activeLanguageCode == 'en'
        ? const [
            'Jan',
            'Feb',
            'Mar',
            'Apr',
            'May',
            'Jun',
            'Jul',
            'Aug',
            'Sep',
            'Oct',
            'Nov',
            'Dec',
          ]
        : const [
            'Jan',
            'Fév',
            'Mar',
            'Avr',
            'Mai',
            'Juin',
            'Juil',
            'Aoû',
            'Sep',
            'Oct',
            'Nov',
            'Déc',
          ];
    final weekLabels = _activeLanguageCode == 'en'
        ? const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
        : const ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
    final starts = <({DateTime start, DateTime end, String label})>[];
    if (selectedPeriod == 'Aujourd’hui') {
      final day = DateTime(now.year, now.month, now.day);
      for (var hour = 0; hour < 24; hour += 4) {
        final start = day.add(Duration(hours: hour));
        starts.add((
          start: start,
          end: start.add(const Duration(hours: 4)),
          label: '${hour.toString().padLeft(2, '0')}h',
        ));
      }
    } else if (selectedPeriod == 'Cette semaine') {
      final today = DateTime(now.year, now.month, now.day);
      final monday = today.subtract(Duration(days: today.weekday - 1));
      for (var day = 0; day < 7; day++) {
        final start = monday.add(Duration(days: day));
        starts.add((
          start: start,
          end: start.add(const Duration(days: 1)),
          label: weekLabels[day],
        ));
      }
    } else if (selectedPeriod == 'Ce mois') {
      final first = DateTime(now.year, now.month, 1);
      for (
        var day = 1;
        day <= DateTime(now.year, now.month + 1, 0).day;
        day += 7
      ) {
        final start = DateTime(now.year, now.month, day);
        final candidateEnd = DateTime(now.year, now.month, day + 7);
        final monthEnd = DateTime(now.year, now.month + 1, 1);
        final end = candidateEnd.isAfter(monthEnd) ? monthEnd : candidateEnd;
        starts.add((start: start, end: end, label: 'S${((day - 1) ~/ 7) + 1}'));
      }
      if (starts.isEmpty)
        starts.add((
          start: first,
          end: DateTime(now.year, now.month + 1, 1),
          label: monthLabels[now.month - 1],
        ));
    } else if (selectedPeriod == 'Cette année') {
      for (var month = 1; month <= 12; month++) {
        final start = DateTime(now.year, month, 1);
        starts.add((
          start: start,
          end: DateTime(now.year, month + 1, 1),
          label: monthLabels[month - 1],
        ));
      }
    } else {
      final dates = [
        ...sales.map((sale) => sale.date),
        ...expenses.map((expense) => expense.date),
      ];
      final firstYear = dates.isEmpty
          ? now.year
          : dates.map((date) => date.year).reduce((a, b) => a < b ? a : b);
      for (var year = firstYear; year <= now.year; year++) {
        starts.add((
          start: DateTime(year, 1, 1),
          end: DateTime(year + 1, 1, 1),
          label: year.toString(),
        ));
      }
    }
    final buckets = <_ProfitCostBucket>[];
    for (final range in starts) {
      final start = range.start;
      final end = range.end;
      final bucket = _ProfitCostBucket(start: start, label: range.label);
      for (final sale in sales.where(
        (sale) => !sale.date.isBefore(start) && sale.date.isBefore(end),
      )) {
        bucket.revenue += sale.total;
        bucket.goodsCost += sale.stockQuantity * sale.product.purchasePrice;
      }
      for (final expense in expenses.where(
        (expense) =>
            !expense.date.isBefore(start) && expense.date.isBefore(end),
      )) {
        bucket.operatingExpenses += expense.amount;
      }
      buckets.add(bucket);
    }
    return buckets;
  }

  String get _overviewCaption => switch (selectedPeriod) {
    'Aujourd’hui' => _tr(
      'Évolution par tranche de 4 heures, pour aujourd’hui.',
      'Activity in four-hour intervals for today.',
    ),
    'Cette semaine' => _tr(
      'Ventes, coûts et bénéfices jour par jour cette semaine.',
      'Sales, costs and profit by day this week.',
    ),
    'Ce mois' => _tr(
      'Ventes, coûts et bénéfices par semaine ce mois-ci.',
      'Sales, costs and profit by week this month.',
    ),
    'Cette année' => _tr(
      'Ventes, coûts et bénéfices mois par mois cette année.',
      'Sales, costs and profit by month this year.',
    ),
    _ => _tr(
      'Ventes, coûts et bénéfices par année, depuis vos premiers enregistrements.',
      'Sales, costs and profit by year since your first records.',
    ),
  };

  List<_DashboardActivity> _recentActivities() {
    final items = <_DashboardActivity>[
      ...sales.map(
        (sale) => _DashboardActivity(
          date: sale.date,
          title: '${_tr('Vente', 'Sale')} • ${sale.receiptNumber}',
          subtitle: '${sale.customerName} • ${_money(sale.total)}',
          icon: Icons.point_of_sale_outlined,
          color: teal,
        ),
      ),
      ...purchases.map(
        (purchase) => _DashboardActivity(
          date: purchase.date,
          title:
              '${_tr('Approvisionnement', 'Purchase')} • ${purchase.product.name}',
          subtitle:
              '${_quantity(purchase.quantity)} ${purchase.product.unit} • ${_money(purchase.totalCost)}',
          icon: Icons.local_shipping_outlined,
          color: const Color(0xFFD88931),
        ),
      ),
      ...expenses.map(
        (expense) => _DashboardActivity(
          date: expense.date,
          title: '${_tr('Dépense', 'Expense')} • ${expense.title}',
          subtitle: '${expense.category} • ${_money(expense.amount)}',
          icon: Icons.receipt_long_outlined,
          color: const Color(0xFF527ACB),
        ),
      ),
    ]..sort((a, b) => b.date.compareTo(a.date));
    return items.take(5).toList();
  }

  @override
  Widget build(BuildContext context) {
    final activities = _recentActivities();
    final insights = businessInsights;
    final creditCustomers = indebtedCustomerCount;
    final pendingPickups = pendingPickupCount;
    final lowStockCount = lowStockProducts.length;
    final expiredCount = expiredProducts.length;
    final expiringSoonCount = productsExpiringSoon.length;
    final lateCustomerCount = overdueCustomerCount;
    final belowCostProducts = products
        .where(
          (product) =>
              product.retailUnitsPerStockUnit > 0 &&
              product.retailPrice <
                  product.purchasePrice / product.retailUnitsPerStockUnit,
        )
        .toList();

    return SingleChildScrollView(
      padding: EdgeInsets.all(isDesktop ? 32 : 18),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _BizPageHero(
                title: currentPage == 'Accueil'
                    ? _tr('Bonjour 👋', 'Hello 👋')
                    : _localizedPageName(currentPage),
                subtitle: selectedPeriod == 'Tout'
                    ? _tr(
                        'Vue cumulée depuis tes premiers enregistrements.',
                        'Totals since your first records.',
                      )
                    : _tr(
                        'Les chiffres de ton commerce, sur la période choisie.',
                        'Your business at a glance for the selected period.',
                      ),
                icon: Icons.dashboard_rounded,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    _tr('Afficher :', 'Show:'),
                    style: TextStyle(
                      color: Colors.black54,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFDCE3EA)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: selectedPeriod,
                        borderRadius: BorderRadius.circular(12),
                        items:
                            const [
                                  'Aujourd’hui',
                                  'Cette semaine',
                                  'Ce mois',
                                  'Cette année',
                                  'Tout',
                                ]
                                .map(
                                  (period) => DropdownMenuItem(
                                    value: period,
                                    child: Text(_periodLabel(period)),
                                  ),
                                )
                                .toList(),
                        onChanged: (period) {
                          if (period != null) onPeriodChanged(period);
                        },
                      ),
                    ),
                  ),
                  if (selectedPeriod != 'Tout')
                    Text(
                      _tr(
                        'Du ${_date(_periodStart())} à aujourd’hui',
                        'From ${_date(_periodStart())} to today',
                      ),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black45,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                _tr(
                  'Chiffre d’affaires, achats et dépenses suivent la période. Stock et crédits affichent les soldes actuels.',
                  'Sales, purchases and expenses follow the selected period. Inventory and customer balances show current totals.',
                ),
                style: TextStyle(fontSize: 12, color: Colors.black45),
              ),
              const SizedBox(height: 24),
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 1000 ? 4 : 2;

                  return GridView.count(
                    crossAxisCount: columns,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                    childAspectRatio: columns == 4 ? 1.55 : 1.32,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      SummaryCard(
                        title: _tr('Chiffre d’affaires', 'Sales revenue'),
                        value: _money(periodRevenue),
                        icon: Icons.payments_outlined,
                        color: teal,
                      ),
                      SummaryCard(
                        title: _tr('Approvisionnement', 'Purchases'),
                        value: _money(totalPurchaseCost),
                        icon: Icons.inventory_2_outlined,
                        color: Color(0xFFD88931),
                      ),
                      SummaryCard(
                        title: _tr(
                          'Bénéfice net estimé',
                          'Estimated net profit',
                        ),
                        value: _money(netProfit),
                        icon: Icons.trending_up_outlined,
                        color: const Color(0xFF27966F),
                      ),
                      SummaryCard(
                        title: _tr('Crédits clients', 'Customer credit'),
                        value: _money(totalCredit),
                        icon: Icons.account_balance_wallet_outlined,
                        color: const Color(0xFFB84A52),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _tr('Indicateurs clés', 'Key indicators'),
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.bold,
                          color: navy,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _overviewCaption,
                        style: const TextStyle(color: Colors.black54),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        height: 190,
                        child: _ProfitCostChart(buckets: _overviewBuckets()),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 16,
                        runSpacing: 8,
                        children: [
                          _ChartTrendLegend(
                            color: const Color(0xFF20D6E8),
                            label: _tr('Ventes', 'Sales'),
                            values: _overviewBuckets()
                                .map((b) => b.revenue)
                                .toList(),
                          ),
                          _ChartTrendLegend(
                            color: const Color(0xFFB57CFF),
                            label: _tr(
                              'Coûts des ventes + dépenses',
                              'Cost of sales + expenses',
                            ),
                            values: _overviewBuckets()
                                .map((b) => b.totalCosts)
                                .toList(),
                          ),
                          _ChartTrendLegend(
                            color: const Color(0xFFFF8C73),
                            label: _tr('Bénéfice net', 'Net profit'),
                            values: _overviewBuckets()
                                .map((b) => b.profit)
                                .toList(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _dashboardStatChip(
                            _tr('Ventes enregistrées', 'Recorded sales'),
                            periodSales.length.toString(),
                            Icons.receipt_long_outlined,
                          ),
                          _dashboardStatChip(
                            _tr('Panier moyen', 'Average basket'),
                            _money(averageTicket),
                            Icons.shopping_basket_outlined,
                          ),
                          _dashboardStatChip(
                            _tr('Dépenses', 'Expenses'),
                            _money(periodExpenseTotal),
                            Icons.money_off_csred_outlined,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Card(
                color: const Color(0xFFF4F8F7),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: const BorderSide(color: Color(0xFFDDEBE7)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.auto_awesome, color: teal),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              _tr('Conseils malins', 'Smart insights'),
                              style: const TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.bold,
                                color: ink,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              _tr('Gratuit • hors ligne', 'Free • offline'),
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: teal,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        _tr(
                          'Des repères calculés à partir de vos ventes et de votre stock, directement dans l’application.',
                          'Helpful signals calculated from your sales and inventory, right in the app.',
                        ),
                        style: const TextStyle(color: Colors.black54),
                      ),
                      const SizedBox(height: 12),
                      if (insights.isEmpty)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(
                            Icons.insights_outlined,
                            color: teal,
                          ),
                          title: Text(
                            _tr(
                              'L’analyse démarre avec vos ventes',
                              'Insights start with your sales',
                            ),
                          ),
                          subtitle: Text(
                            _tr(
                              'Enregistrez quelques ventes pour voir les produits qui marchent et les stocks à surveiller.',
                              'Record a few sales to see what is selling and which stock to watch.',
                            ),
                          ),
                        )
                      else
                        ...insights.map(
                          (insight) => Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(13),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(insight.icon, color: insight.color),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          insight.title,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            color: ink,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          insight.detail,
                                          style: const TextStyle(
                                            color: Colors.black54,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              LocalAssistantCard(
                businessId: businessId,
                periodSales: periodSales,
                allSales: sales,
                products: products,
                purchases: purchases,
                payments: payments,
                expenses: expenses,
                refunds: refunds,
                cashMovements: cashMovements,
                canUseOnlineAI: canUseOnlineAI,
                canSeeFullData: canSeeFullData,
                periodRevenue: periodRevenue,
                netProfit: netProfit,
                selectedPeriod: selectedPeriod,
              ),
              const SizedBox(height: 24),
              Card(
                color: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: const BorderSide(color: Color(0xFFE8EDEF)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _tr('Patrimoine & stock', 'Assets & inventory'),
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.bold,
                          color: ink,
                        ),
                      ),
                      const SizedBox(height: 18),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final columns = constraints.maxWidth >= 650 ? 3 : 1;
                          final width =
                              (constraints.maxWidth - (columns - 1) * 16) /
                              columns;
                          return Wrap(
                            spacing: 16,
                            runSpacing: 16,
                            children: [
                              _stockMetric(
                                width: width,
                                label: _tr(
                                  'Valeur du stock au coût d’achat',
                                  'Inventory value at cost',
                                ),
                                value: _money(stockValue),
                                color: teal,
                              ),
                              _stockMetric(
                                width: width,
                                label: _tr(
                                  'Bénéfice potentiel restant',
                                  'Remaining potential profit',
                                ),
                                value: _money(potentialStockProfit),
                                color: const Color(0xFF27966F),
                              ),
                              _stockMetric(
                                width: width,
                                label: _tr(
                                  'Produits à réapprovisionner',
                                  'Products to restock',
                                ),
                                value: lowStockCount.toString(),
                                color: lowStockCount == 0
                                    ? teal
                                    : const Color(0xFFB84A52),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              _sectionTitle(_tr('Alertes prioritaires', 'Priority alerts')),
              const SizedBox(height: 10),
              if (expiredCount == 0 &&
                  expiringSoonCount == 0 &&
                  lowStockCount == 0 &&
                  belowCostProducts.isEmpty &&
                  lateCustomerCount == 0 &&
                  creditCustomers == 0 &&
                  pendingPickups == 0)
                Card(
                  color: Colors.white,
                  elevation: 0,
                  child: ListTile(
                    leading: Icon(Icons.check_circle_outline, color: teal),
                    title: Text(
                      _tr(
                        'Tout est sous contrôle',
                        'Everything is under control',
                      ),
                    ),
                    subtitle: Text(
                      _tr(
                        'Les péremptions, stocks bas, prix sous le coût d’achat, crédits échus et retraits apparaîtront ici.',
                        'Expiring items, low stock, prices below cost, overdue balances and pending pickups will appear here.',
                      ),
                    ),
                  ),
                )
              else ...[
                if (expiredCount > 0)
                  _alertTile(
                    icon: Icons.error_outline_rounded,
                    title: _tr(
                      '$expiredCount produit(s) déjà périmé(s)',
                      '$expiredCount expired product(s)',
                    ),
                    subtitle: expiredProducts
                        .take(2)
                        .map((product) => product.name)
                        .join(' • '),
                    count: expiredCount,
                    color: const Color(0xFFB3261E),
                    onTap: onOpenStock,
                  ),
                if (lateCustomerCount > 0)
                  _alertTile(
                    icon: Icons.access_time_rounded,
                    title: _tr(
                      '$lateCustomerCount client(s) ont un crédit en retard',
                      '$lateCustomerCount customer(s) have overdue credit',
                    ),
                    subtitle: _tr(
                      '${_money(overdueBalance)} à recouvrer après échéance',
                      '${_money(overdueBalance)} overdue',
                    ),
                    count: lateCustomerCount,
                    color: const Color(0xFFB3261E),
                    onTap: onOpenCustomers,
                  ),
                if (expiringSoonCount > 0)
                  _alertTile(
                    icon: Icons.schedule_outlined,
                    title: _tr(
                      '$expiringSoonCount produit(s) à surveiller avant péremption',
                      '$expiringSoonCount product(s) expiring soon',
                    ),
                    subtitle: productsExpiringSoon
                        .take(2)
                        .map((product) {
                          final days = _daysUntilExpiry(product)!;
                          return days == 0
                              ? '${product.name} • ${_tr('aujourd’hui', 'today')}'
                              : '${product.name} • $days ${_tr('j', 'd')}';
                        })
                        .join('  |  '),
                    count: expiringSoonCount,
                    color: const Color(0xFFD88931),
                    onTap: onOpenStock,
                  ),
                if (lowStockCount > 0)
                  _alertTile(
                    icon: Icons.warning_amber_rounded,
                    title: _tr(
                      '$lowStockCount produit(s) sous le seuil de stock',
                      '$lowStockCount product(s) below the stock threshold',
                    ),
                    subtitle: lowStockProducts
                        .take(2)
                        .map((product) => product.name)
                        .join(' • '),
                    count: lowStockCount,
                    color: const Color(0xFFB84A52),
                    onTap: onOpenStock,
                  ),
                if (belowCostProducts.isNotEmpty)
                  _alertTile(
                    icon: Icons.price_change_outlined,
                    title: _tr(
                      '${belowCostProducts.length} prix de vente sous le coût d’achat',
                      '${belowCostProducts.length} selling prices below purchase cost',
                    ),
                    subtitle: belowCostProducts
                        .take(3)
                        .map((product) => product.name)
                        .join(' • '),
                    count: belowCostProducts.length,
                    color: const Color(0xFFB3261E),
                    onTap: onOpenStock,
                  ),
                if (creditCustomers > 0)
                  _alertTile(
                    icon: Icons.account_balance_wallet_outlined,
                    title: _tr(
                      '$creditCustomers client(s) ont un crédit en cours',
                      '$creditCustomers customer(s) have outstanding credit',
                    ),
                    subtitle: _tr(
                      '${_money(totalCredit)} restent à encaisser',
                      '${_money(totalCredit)} to collect',
                    ),
                    count: creditCustomers,
                    color: const Color(0xFFD88931),
                    onTap: onOpenCustomers,
                  ),
                if (pendingPickups > 0)
                  _alertTile(
                    icon: Icons.inventory_2_outlined,
                    title: _tr(
                      '$pendingPickups commande(s) à retirer',
                      '$pendingPickups order(s) awaiting pickup',
                    ),
                    subtitle: _tr(
                      'Vérifiez les colis qui attendent leur client.',
                      'Check orders waiting for customer pickup.',
                    ),
                    count: pendingPickups,
                    color: teal,
                    onTap: onOpenSales,
                  ),
              ],
              const SizedBox(height: 24),
              _sectionTitle(_tr('Actions rapides', 'Quick actions')),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  OutlinedButton.icon(
                    onPressed: onOpenSales,
                    icon: const Icon(Icons.add_shopping_cart),
                    label: Text(_tr('Nouvelle vente', 'New sale')),
                  ),
                  OutlinedButton.icon(
                    onPressed: onOpenPurchases,
                    icon: const Icon(Icons.local_shipping_outlined),
                    label: Text(_tr('Nouvel achat', 'New purchase')),
                  ),
                  OutlinedButton.icon(
                    onPressed: onAddProduct,
                    icon: const Icon(Icons.add_box_outlined),
                    label: Text(_tr('Ajouter un produit', 'Add a product')),
                  ),
                  OutlinedButton.icon(
                    onPressed: onOpenExpenses,
                    icon: const Icon(Icons.receipt_long_outlined),
                    label: Text(_tr('Voir les dépenses', 'View expenses')),
                  ),
                  if (canManageData)
                    OutlinedButton.icon(
                      onPressed: onExportBackup,
                      icon: const Icon(Icons.backup_outlined),
                      label: Text(
                        _tr('Sauvegarder mes données', 'Back up my data'),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              _sectionTitle(_tr('Activité récente', 'Recent activity')),
              const SizedBox(height: 10),
              if (activities.isEmpty)
                Card(
                  color: Colors.white,
                  elevation: 0,
                  child: ListTile(
                    leading: const Icon(Icons.history, color: teal),
                    title: Text(
                      _tr('Aucune activité pour le moment', 'No activity yet'),
                    ),
                    subtitle: Text(
                      _tr(
                        'Vos ventes, achats et dépenses récentes seront regroupés ici.',
                        'Your recent sales, purchases and expenses will appear here.',
                      ),
                    ),
                    trailing: TextButton(
                      onPressed: onOpenStock,
                      child: Text(_tr('Voir le stock', 'View inventory')),
                    ),
                  ),
                )
              else
                Card(
                  color: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                    side: const BorderSide(color: Color(0xFFE8EDEF)),
                  ),
                  child: Column(
                    children: [
                      for (
                        var index = 0;
                        index < activities.length;
                        index++
                      ) ...[
                        ListTile(
                          leading: CircleAvatar(
                            backgroundColor: activities[index].color.withValues(
                              alpha: 0.12,
                            ),
                            child: Icon(
                              activities[index].icon,
                              color: activities[index].color,
                            ),
                          ),
                          title: Text(
                            activities[index].title,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            '${activities[index].subtitle} • ${_date(activities[index].date)}',
                          ),
                        ),
                        if (index < activities.length - 1)
                          const Divider(height: 1, indent: 72, endIndent: 16),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) => Text(
    title,
    style: const TextStyle(
      fontSize: 19,
      fontWeight: FontWeight.bold,
      color: ink,
    ),
  );

  Widget _dashboardStatChip(String label, String value, IconData icon) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F7FA),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: teal),
            const SizedBox(width: 7),
            Text(
              '$label : ',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
            Text(
              value,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: ink,
              ),
            ),
          ],
        ),
      );

  Widget _stockMetric({
    required double width,
    required String label,
    required String value,
    required Color color,
  }) => SizedBox(
    width: width,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 13, color: Colors.black54),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    ),
  );

  Widget _alertTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required int count,
    required Color color,
    required VoidCallback onTap,
  }) => Card(
    color: Colors.white,
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: Color(0xFFE8EDEF)),
    ),
    child: ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.12),
        child: Icon(icon, color: color),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          count.toString(),
          style: TextStyle(color: color, fontWeight: FontWeight.bold),
        ),
      ),
    ),
  );
}

class Product {
  Product({
    String? recordId,
    required this.name,
    required this.category,
    required this.quantity,
    required this.unit,
    required this.retailUnit,
    required this.retailUnitsPerStockUnit,
    required this.purchasePrice,
    required this.wholesalePrice,
    required this.retailPrice,
    required this.lowStockLimit,
    this.barcode = '',
    this.marketPrice,
    this.photoPath,
    this.photoCredit,
    this.photoPageUrl,
    this.photoPhotographerUrl,
    this.expirationDate,
  }) : recordId = recordId ?? _newRecordId();

  final String recordId;
  final String name;
  final String category;
  final double quantity;
  final String unit;
  final String retailUnit;
  final double retailUnitsPerStockUnit;
  final double purchasePrice;
  final double wholesalePrice;
  final double retailPrice;
  final double lowStockLimit;
  final String barcode;
  final double? marketPrice;
  final String? photoPath;
  final String? photoCredit;
  final String? photoPageUrl;
  final String? photoPhotographerUrl;
  final DateTime? expirationDate;

  Map<String, dynamic> toJson({bool includeRecordId = true}) => {
    if (includeRecordId) 'recordId': recordId,
    'name': name,
    'category': category,
    'quantity': quantity,
    'unit': unit,
    'retailUnit': retailUnit,
    'retailUnitsPerStockUnit': retailUnitsPerStockUnit,
    'purchasePrice': purchasePrice,
    'wholesalePrice': wholesalePrice,
    'retailPrice': retailPrice,
    'lowStockLimit': lowStockLimit,
    'barcode': barcode,
    'marketPrice': marketPrice,
    'photoPath': photoPath,
    'photoCredit': photoCredit,
    'photoPageUrl': photoPageUrl,
    'photoPhotographerUrl': photoPhotographerUrl,
    'expirationDate': expirationDate?.toIso8601String(),
  };

  factory Product.fromJson(Map<String, dynamic> json) => Product(
    recordId: json['recordId'] as String?,
    name: json['name'] as String,
    category: json['category'] as String,
    quantity: (json['quantity'] as num).toDouble(),
    unit: json['unit'] as String,
    retailUnit: json['retailUnit'] as String,
    retailUnitsPerStockUnit: (json['retailUnitsPerStockUnit'] as num)
        .toDouble(),
    purchasePrice: (json['purchasePrice'] as num).toDouble(),
    wholesalePrice: (json['wholesalePrice'] as num).toDouble(),
    retailPrice: (json['retailPrice'] as num).toDouble(),
    lowStockLimit: (json['lowStockLimit'] as num).toDouble(),
    barcode: json['barcode'] as String? ?? '',
    marketPrice: (json['marketPrice'] as num?)?.toDouble(),
    photoPath: json['photoPath'] as String?,
    photoCredit: json['photoCredit'] as String?,
    photoPageUrl: json['photoPageUrl'] as String?,
    photoPhotographerUrl: json['photoPhotographerUrl'] as String?,
    expirationDate: DateTime.tryParse(json['expirationDate'] as String? ?? ''),
  );

  Product copyWith({
    String? name,
    double? quantity,
    String? retailUnit,
    double? purchasePrice,
    double? wholesalePrice,
    double? retailPrice,
    double? retailUnitsPerStockUnit,
    double? marketPrice,
    double? lowStockLimit,
    String? barcode,
    String? photoPath,
    String? photoCredit,
    String? photoPageUrl,
    String? photoPhotographerUrl,
    DateTime? expirationDate,
    bool clearExpirationDate = false,
    bool clearMarketPrice = false,
    bool clearPhotoPath = false,
    bool clearPhotoMetadata = false,
  }) => Product(
    recordId: recordId,
    name: name ?? this.name,
    category: category,
    quantity: quantity ?? this.quantity,
    unit: unit,
    retailUnit: retailUnit ?? this.retailUnit,
    retailUnitsPerStockUnit:
        retailUnitsPerStockUnit ?? this.retailUnitsPerStockUnit,
    purchasePrice: purchasePrice ?? this.purchasePrice,
    wholesalePrice: wholesalePrice ?? this.wholesalePrice,
    retailPrice: retailPrice ?? this.retailPrice,
    lowStockLimit: lowStockLimit ?? this.lowStockLimit,
    barcode: barcode ?? this.barcode,
    marketPrice: clearMarketPrice ? null : marketPrice ?? this.marketPrice,
    photoPath: clearPhotoPath ? null : photoPath ?? this.photoPath,
    photoCredit: clearPhotoMetadata ? null : photoCredit ?? this.photoCredit,
    photoPageUrl: clearPhotoMetadata ? null : photoPageUrl ?? this.photoPageUrl,
    photoPhotographerUrl: clearPhotoMetadata
        ? null
        : photoPhotographerUrl ?? this.photoPhotographerUrl,
    expirationDate: clearExpirationDate
        ? null
        : expirationDate ?? this.expirationDate,
  );
}

class SupplierRecord {
  SupplierRecord({
    String? recordId,
    required this.name,
    this.phone = '',
    this.email = '',
    this.address = '',
    this.notes = '',
  }) : recordId = recordId ?? _newRecordId();

  final String recordId;
  final String name;
  final String phone;
  final String email;
  final String address;
  final String notes;

  Map<String, dynamic> toJson() => {
    'recordId': recordId,
    'name': name,
    'phone': phone,
    'email': email,
    'address': address,
    'notes': notes,
  };

  factory SupplierRecord.fromJson(Map<String, dynamic> json) => SupplierRecord(
    recordId: json['recordId'] as String?,
    name: json['name'] as String? ?? '',
    phone: json['phone'] as String? ?? '',
    email: json['email'] as String? ?? '',
    address: json['address'] as String? ?? '',
    notes: json['notes'] as String? ?? '',
  );
}

class BusinessProfile {
  const BusinessProfile({
    this.phone = '',
    this.address = '',
    this.receiptFooter = 'Merci pour votre confiance !',
    this.logoUrl = '',
    this.countryCode = 'BJ',
    this.currencyCode = 'XOF',
    this.languageCode = 'fr',
  });

  final String phone;
  final String address;
  final String receiptFooter;
  final String logoUrl;
  final String countryCode;
  final String currencyCode;
  final String languageCode;

  Map<String, dynamic> toJson() => {
    'phone': phone,
    'address': address,
    'receiptFooter': receiptFooter,
    'logoUrl': logoUrl,
    'countryCode': countryCode,
    'currencyCode': currencyCode,
    'languageCode': languageCode,
  };

  factory BusinessProfile.fromJson(Map<String, dynamic> json) =>
      BusinessProfile(
        phone: json['phone'] as String? ?? '',
        address: json['address'] as String? ?? '',
        receiptFooter:
            json['receiptFooter'] as String? ?? 'Merci pour votre confiance !',
        logoUrl: json['logoUrl'] as String? ?? '',
        countryCode: json['countryCode'] as String? ?? 'BJ',
        currencyCode: json['currencyCode'] as String? ?? 'XOF',
        languageCode: json['languageCode'] as String? ?? 'fr',
      );
}

class BusinessProfileDialog extends StatefulWidget {
  const BusinessProfileDialog({
    super.key,
    required this.profile,
    required this.canChangeMarket,
  });
  final BusinessProfile profile;
  final bool canChangeMarket;

  @override
  State<BusinessProfileDialog> createState() => _BusinessProfileDialogState();
}

class _BusinessProfileDialogState extends State<BusinessProfileDialog> {
  final _formKey = GlobalKey<FormState>();
  late _MarketOption selectedMarket = _marketOptions.firstWhere(
    (market) => market.countryCode == widget.profile.countryCode,
    orElse: () => _marketOptions.first,
  );
  late String selectedLanguageCode = widget.profile.languageCode == 'en'
      ? 'en'
      : 'fr';
  late final phone = TextEditingController(text: widget.profile.phone);
  late final address = TextEditingController(text: widget.profile.address);
  late final footer = TextEditingController(text: widget.profile.receiptFooter);
  late final logoUrl = TextEditingController(text: widget.profile.logoUrl);

  @override
  void dispose() {
    phone.dispose();
    address.dispose();
    footer.dispose();
    logoUrl.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      BusinessProfile(
        phone: phone.text.trim(),
        address: address.text.trim(),
        receiptFooter: footer.text.trim().isEmpty
            ? 'Merci pour votre confiance !'
            : footer.text.trim(),
        logoUrl: logoUrl.text.trim(),
        countryCode: selectedMarket.countryCode,
        currencyCode: selectedMarket.currencyCode,
        languageCode: selectedLanguageCode,
      ),
    );
  }

  Future<void> _chooseMarket() async {
    if (!widget.canChangeMarket) return;
    final market = await showDialog<_MarketOption>(
      context: context,
      builder: (_) => _MarketPickerDialog(
        selectedMarket: selectedMarket,
        languageCode: selectedLanguageCode,
      ),
    );
    if (market != null && mounted) {
      setState(() => selectedMarket = market);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(_tr('Réglages du commerce', 'Business settings')),
    content: SizedBox(
      width: _dialogWidth(context, 480),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: selectedLanguageCode,
                decoration: InputDecoration(
                  labelText: _tr('Langue de l’interface', 'Interface language'),
                  prefixIcon: const Icon(Icons.translate_outlined),
                ),
                items: [
                  DropdownMenuItem(
                    value: 'fr',
                    child: Text(_tr('Français', 'French')),
                  ),
                  DropdownMenuItem(
                    value: 'en',
                    child: Text(_tr('Anglais', 'English')),
                  ),
                ],
                onChanged: (language) => setState(() {
                  if (language != null) selectedLanguageCode = language;
                }),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _tr(
                    'L’interface utilise les textes traduits selon cette langue. Les noms de produits, clients et notes restent dans la langue saisie.',
                    'Interface text follows this language. Product and customer names, and notes, stay as entered.',
                  ),
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: ValueKey(
                  '${selectedMarket.countryCode}:$selectedLanguageCode',
                ),
                initialValue: selectedMarket.labelFor(selectedLanguageCode),
                readOnly: true,
                onTap: widget.canChangeMarket ? _chooseMarket : null,
                decoration: InputDecoration(
                  labelText: _tr(
                    'Pays et devise du commerce',
                    'Country and currency',
                  ),
                  prefixIcon: const Icon(Icons.public_outlined),
                  suffixIcon: const Icon(Icons.search_rounded),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  widget.canChangeMarket
                      ? _tr(
                          'Devise utilisée pour les nouveaux montants : ${selectedMarket.currencyCode}.',
                          'Currency used for new amounts: ${selectedMarket.currencyCode}.',
                        )
                      : _tr(
                          'Le pays et la devise sont verrouillés car ce commerce contient déjà des montants. Cela évite de réinterpréter les ventes et achats existants.',
                          'Country and currency are locked because this business already has amounts, to preserve the meaning of existing sales and purchases.',
                        ),
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: phone,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: _tr('Téléphone du commerce', 'Business phone'),
                  prefixIcon: const Icon(Icons.phone_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: address,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: _tr('Adresse du commerce', 'Business address'),
                  prefixIcon: const Icon(Icons.place_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: logoUrl,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'Lien du logo (facultatif)',
                  prefixIcon: Icon(Icons.image_outlined),
                  helperText: 'Lien public vers une image PNG ou JPG.',
                ),
                validator: (value) {
                  final text = (value ?? '').trim();
                  if (text.isEmpty) return null;
                  final uri = Uri.tryParse(text);
                  return uri != null &&
                          uri.hasScheme &&
                          (uri.scheme == 'https' || uri.scheme == 'http')
                      ? null
                      : 'Saisis un lien commençant par https://';
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: footer,
                maxLines: 2,
                maxLength: 100,
                decoration: const InputDecoration(
                  labelText: 'Message en bas du reçu',
                ),
              ),
              const SizedBox(height: 4),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Ces informations apparaîtront sur les reçus imprimés et PDF.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Annuler'),
      ),
      FilledButton(onPressed: _save, child: const Text('Enregistrer')),
    ],
  );
}

class _MarketPickerDialog extends StatefulWidget {
  const _MarketPickerDialog({
    required this.selectedMarket,
    required this.languageCode,
  });

  final _MarketOption? selectedMarket;
  final String languageCode;

  @override
  State<_MarketPickerDialog> createState() => _MarketPickerDialogState();
}

class _MarketPickerDialogState extends State<_MarketPickerDialog> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final markets = _marketOptions
        .where((market) {
          if (query.isEmpty) return true;
          return market.countryName.toLowerCase().contains(query) ||
              market.englishCountryName.toLowerCase().contains(query) ||
              market.currencyCode.toLowerCase().contains(query) ||
              market.currencyName.toLowerCase().contains(query);
        })
        .toList(growable: false);
    final isEnglish = widget.languageCode == 'en';

    return AlertDialog(
      title: Text(isEnglish ? 'Choose a country' : 'Choisir un pays'),
      content: SizedBox(
        width: _dialogWidth(context, 480),
        height: _dialogHeight(context, 460),
        child: Column(
          children: [
            TextField(
              controller: _search,
              autofocus: true,
              decoration: InputDecoration(
                labelText: isEnglish
                    ? 'Search country or currency'
                    : 'Rechercher un pays ou une devise',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: isEnglish
                            ? 'Clear search'
                            : 'Effacer la recherche',
                        onPressed: () {
                          _search.clear();
                          setState(() => _query = '');
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: markets.isEmpty
                  ? Center(
                      child: Text(
                        isEnglish
                            ? 'No matching country.'
                            : 'Aucun pays correspondant.',
                      ),
                    )
                  : ListView.builder(
                      itemCount: markets.length,
                      itemBuilder: (context, index) {
                        final market = markets[index];
                        final selected =
                            market.countryCode ==
                            widget.selectedMarket?.countryCode;
                        return ListTile(
                          dense: true,
                          title: Text(market.labelFor(widget.languageCode)),
                          trailing: selected
                              ? const Icon(Icons.check_rounded, color: teal)
                              : null,
                          onTap: () => Navigator.pop(context, market),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(isEnglish ? 'Cancel' : 'Annuler'),
        ),
      ],
    );
  }
}

class PurchaseRecord {
  PurchaseRecord({
    String? recordId,
    required this.product,
    required this.supplier,
    required this.quantity,
    required this.unitPrice,
    required this.transport,
    required this.meals,
    required this.handling,
    required this.otherExpenses,
    required this.date,
    this.paymentMethod = 'Non précisé',
  }) : recordId = recordId ?? _newRecordId();

  final String recordId;
  final Product product;
  final String supplier;
  final double quantity;
  final double unitPrice;
  final double transport;
  final double meals;
  final double handling;
  final double otherExpenses;
  final DateTime date;
  final String paymentMethod;

  double get tripExpenses => transport + meals + handling + otherExpenses;
  double get totalCost => quantity * unitPrice + tripExpenses;

  Map<String, dynamic> toJson() => {
    'recordId': recordId,
    'product': product.toJson(includeRecordId: false),
    'supplier': supplier,
    'quantity': quantity,
    'unitPrice': unitPrice,
    'transport': transport,
    'meals': meals,
    'handling': handling,
    'otherExpenses': otherExpenses,
    'date': date.toIso8601String(),
    'paymentMethod': paymentMethod,
  };
  factory PurchaseRecord.fromJson(Map<String, dynamic> json) => PurchaseRecord(
    recordId: json['recordId'] as String?,
    product: Product.fromJson(Map<String, dynamic>.from(json['product'])),
    supplier: json['supplier'] as String,
    quantity: (json['quantity'] as num).toDouble(),
    unitPrice: (json['unitPrice'] as num).toDouble(),
    transport: (json['transport'] as num).toDouble(),
    meals: (json['meals'] as num).toDouble(),
    handling: (json['handling'] as num).toDouble(),
    otherExpenses: (json['otherExpenses'] as num).toDouble(),
    date: DateTime.parse(json['date'] as String),
    paymentMethod: json['paymentMethod'] as String? ?? 'Non précisé',
  );
}

class SaleRecord {
  SaleRecord({
    String? recordId,
    required this.receiptNumber,
    required this.product,
    required this.customerName,
    required this.customerPhone,
    required this.quantity,
    required this.saleUnit,
    required this.stockQuantity,
    required this.unitPrice,
    required this.total,
    required this.received,
    required this.balance,
    required this.paymentMethod,
    required this.date,
    required this.dueDate,
    this.pickupStatus = 'Remis au client',
    this.collectedAt,
    this.initialReceived,
  }) : recordId = recordId ?? _newRecordId();

  final String recordId;
  final String receiptNumber;
  final Product product;
  final String customerName;
  final String customerPhone;
  final double quantity;
  final String saleUnit;
  final double stockQuantity;
  final double unitPrice;
  final double total;
  final double received;
  final double balance;
  final String paymentMethod;
  final DateTime date;
  final DateTime? dueDate;
  final String pickupStatus;
  final DateTime? collectedAt;
  final double? initialReceived;

  Map<String, dynamic> toJson() => {
    'recordId': recordId,
    'receiptNumber': receiptNumber,
    'product': product.toJson(includeRecordId: false),
    'customerName': customerName,
    'customerPhone': customerPhone,
    'quantity': quantity,
    'saleUnit': saleUnit,
    'stockQuantity': stockQuantity,
    'unitPrice': unitPrice,
    'total': total,
    'received': received,
    'balance': balance,
    'paymentMethod': paymentMethod,
    'date': date.toIso8601String(),
    'dueDate': dueDate?.toIso8601String(),
    'pickupStatus': pickupStatus,
    'collectedAt': collectedAt?.toIso8601String(),
    'initialReceived': initialReceived,
  };
  factory SaleRecord.fromJson(Map<String, dynamic> json) => SaleRecord(
    recordId: json['recordId'] as String?,
    receiptNumber: json['receiptNumber'] as String,
    product: Product.fromJson(Map<String, dynamic>.from(json['product'])),
    customerName: json['customerName'] as String,
    customerPhone: json['customerPhone'] as String,
    quantity: (json['quantity'] as num).toDouble(),
    saleUnit: json['saleUnit'] as String,
    stockQuantity: (json['stockQuantity'] as num).toDouble(),
    unitPrice: (json['unitPrice'] as num).toDouble(),
    total: (json['total'] as num).toDouble(),
    received: (json['received'] as num).toDouble(),
    balance: (json['balance'] as num).toDouble(),
    paymentMethod: json['paymentMethod'] as String,
    date: DateTime.parse(json['date'] as String),
    dueDate: json['dueDate'] == null
        ? null
        : DateTime.parse(json['dueDate'] as String),
    pickupStatus: json['pickupStatus'] as String? ?? 'Remis au client',
    collectedAt: json['collectedAt'] == null
        ? null
        : DateTime.parse(json['collectedAt'] as String),
    initialReceived: (json['initialReceived'] as num?)?.toDouble(),
  );

  double get grossProfit => total - (stockQuantity * product.purchasePrice);

  SaleRecord copyWith({Product? product, double? stockQuantity}) => SaleRecord(
    recordId: recordId,
    receiptNumber: receiptNumber,
    product: product ?? this.product,
    customerName: customerName,
    customerPhone: customerPhone,
    quantity: quantity,
    saleUnit: saleUnit,
    stockQuantity: stockQuantity ?? this.stockQuantity,
    unitPrice: unitPrice,
    total: total,
    received: received,
    balance: balance,
    paymentMethod: paymentMethod,
    date: date,
    dueDate: dueDate,
    pickupStatus: pickupStatus,
    collectedAt: collectedAt,
    initialReceived: initialReceived,
  );

  SaleRecord withPayment(double amount) => SaleRecord(
    recordId: recordId,
    receiptNumber: receiptNumber,
    product: product,
    customerName: customerName,
    customerPhone: customerPhone,
    quantity: quantity,
    saleUnit: saleUnit,
    stockQuantity: stockQuantity,
    unitPrice: unitPrice,
    total: total,
    received: received + amount,
    balance: balance - amount,
    paymentMethod: paymentMethod,
    date: date,
    dueDate: balance - amount <= 0 ? null : dueDate,
    pickupStatus: pickupStatus,
    collectedAt: collectedAt,
    initialReceived: initialReceived,
  );
}

class PaymentRecord {
  PaymentRecord({
    String? recordId,
    required this.customerName,
    required this.amount,
    required this.paymentMethod,
    required this.receiptNumber,
    required this.date,
    required this.note,
  }) : recordId = recordId ?? _newRecordId();

  final String recordId;
  final String customerName;
  final double amount;
  final String paymentMethod;
  final String receiptNumber;
  final DateTime date;
  final String note;

  Map<String, dynamic> toJson() => {
    'recordId': recordId,
    'customerName': customerName,
    'amount': amount,
    'paymentMethod': paymentMethod,
    'receiptNumber': receiptNumber,
    'date': date.toIso8601String(),
    'note': note,
  };
  factory PaymentRecord.fromJson(Map<String, dynamic> json) => PaymentRecord(
    recordId: json['recordId'] as String?,
    customerName: json['customerName'] as String,
    amount: (json['amount'] as num).toDouble(),
    paymentMethod: json['paymentMethod'] as String,
    receiptNumber: json['receiptNumber'] as String,
    date: DateTime.parse(json['date'] as String),
    note: json['note'] as String,
  );
}

class RefundRecord {
  RefundRecord({
    String? recordId,
    required this.receiptNumber,
    required this.customerName,
    required this.productName,
    required this.quantity,
    required this.saleUnit,
    required this.value,
    required this.cashRefund,
    required this.paymentMethod,
    required this.date,
  }) : recordId = recordId ?? _newRecordId();

  final String recordId;
  final String receiptNumber;
  final String customerName;
  final String productName;
  final double quantity;
  final String saleUnit;
  final double value;
  final double cashRefund;
  final String paymentMethod;
  final DateTime date;

  Map<String, dynamic> toJson() => {
    'recordId': recordId,
    'receiptNumber': receiptNumber,
    'customerName': customerName,
    'productName': productName,
    'quantity': quantity,
    'saleUnit': saleUnit,
    'value': value,
    'cashRefund': cashRefund,
    'paymentMethod': paymentMethod,
    'date': date.toIso8601String(),
  };

  factory RefundRecord.fromJson(Map<String, dynamic> json) => RefundRecord(
    recordId: json['recordId'] as String?,
    receiptNumber: json['receiptNumber'] as String,
    customerName: json['customerName'] as String,
    productName: json['productName'] as String,
    quantity: (json['quantity'] as num).toDouble(),
    saleUnit: json['saleUnit'] as String,
    value: (json['value'] as num).toDouble(),
    cashRefund: (json['cashRefund'] as num).toDouble(),
    paymentMethod: json['paymentMethod'] as String,
    date: DateTime.parse(json['date'] as String),
  );
}

class RefundRequest {
  const RefundRequest({required this.quantity, required this.paymentMethod});
  final double quantity;
  final String paymentMethod;
}

class RefundDialog extends StatefulWidget {
  const RefundDialog({
    super.key,
    required this.sale,
    required this.receiptSales,
  });
  final SaleRecord sale;
  final List<SaleRecord> receiptSales;

  @override
  State<RefundDialog> createState() => _RefundDialogState();
}

class _RefundDialogState extends State<RefundDialog> {
  final formKey = GlobalKey<FormState>();
  final quantity = TextEditingController();
  String paymentMethod = 'Espèces';

  double get _quantity =>
      double.tryParse(quantity.text.trim().replaceAll(',', '.')) ?? 0;
  double get _returnValue => _quantity * widget.sale.unitPrice;
  double get _receiptTotal =>
      widget.receiptSales.fold(0.0, (sum, item) => sum + item.total);
  double get _receiptReceived =>
      widget.receiptSales.fold(0.0, (sum, item) => sum + item.received);
  double get _cashRefund => (_receiptReceived - (_receiptTotal - _returnValue))
      .clamp(0.0, double.infinity)
      .toDouble();

  @override
  void dispose() {
    quantity.dispose();
    super.dispose();
  }

  String? _validateQuantity(String? value) {
    final parsed = double.tryParse((value ?? '').trim().replaceAll(',', '.'));
    if (parsed == null || parsed <= 0)
      return 'Saisis une quantité supérieure à zéro.';
    if (parsed > widget.sale.quantity)
      return 'La quantité dépasse ce qui reste sur cette vente.';
    return null;
  }

  void _save() {
    if (!formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      RefundRequest(quantity: _quantity, paymentMethod: paymentMethod),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Retour produit • ${widget.sale.receiptNumber}'),
    content: SizedBox(
      width: _dialogWidth(context, 460),
      child: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${widget.sale.product.name} • ${widget.sale.customerName}'),
            const SizedBox(height: 12),
            TextFormField(
              controller: quantity,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              validator: _validateQuantity,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Quantité retournée (${widget.sale.saleUnit})',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Valeur du retour : ${_money(_returnValue)}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _quantity <= 0
                  ? 'La valeur à rembourser et le nouveau crédit seront calculés après la saisie de la quantité.'
                  : _cashRefund > 0
                  ? 'Le client a déjà payé plus que le nouveau total. Somme à lui rendre : ${_money(_cashRefund)}.'
                  : 'La valeur du retour sera déduite de sa dette. Aucun remboursement en espèces n’est nécessaire.',
            ),
            if (_cashRefund > 0) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: paymentMethod,
                decoration: const InputDecoration(
                  labelText: 'Mode de remboursement',
                  border: OutlineInputBorder(),
                ),
                items: const ['Espèces', 'Mobile Money', 'Banque']
                    .map(
                      (value) =>
                          DropdownMenuItem(value: value, child: Text(value)),
                    )
                    .toList(),
                onChanged: (value) =>
                    setState(() => paymentMethod = value ?? paymentMethod),
              ),
            ],
            const SizedBox(height: 12),
            const Text(
              'La quantité retournée sera remise en stock et le retour restera dans l’historique.',
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Annuler'),
      ),
      FilledButton(
        onPressed: _save,
        child: const Text('Enregistrer le retour'),
      ),
    ],
  );
}

class CashMovement {
  CashMovement({
    String? recordId,
    required this.description,
    required this.direction,
    required this.amount,
    required this.paymentMethod,
    required this.date,
    this.isAutomatic = false,
  }) : recordId = recordId ?? _newRecordId();

  final String recordId;
  final String description;
  final String direction;
  final double amount;
  final String paymentMethod;
  final DateTime date;
  final bool isAutomatic;

  Map<String, dynamic> toJson() => {
    'recordId': recordId,
    'description': description,
    'direction': direction,
    'amount': amount,
    'paymentMethod': paymentMethod,
    'date': date.toIso8601String(),
  };

  factory CashMovement.fromJson(Map<String, dynamic> json) => CashMovement(
    recordId: json['recordId'] as String?,
    description: json['description'] as String,
    direction: json['direction'] as String,
    amount: (json['amount'] as num).toDouble(),
    paymentMethod: json['paymentMethod'] as String,
    date: DateTime.parse(json['date'] as String),
  );
}

class CashContent extends StatefulWidget {
  const CashContent({
    super.key,
    required this.movements,
    required this.sales,
    required this.payments,
    required this.purchases,
    required this.expenses,
    required this.refunds,
    required this.onAddMovement,
    required this.onDeleteMovement,
  });

  final List<CashMovement> movements;
  final List<SaleRecord> sales;
  final List<PaymentRecord> payments;
  final List<PurchaseRecord> purchases;
  final List<ExpenseRecord> expenses;
  final List<RefundRecord> refunds;
  final VoidCallback onAddMovement;
  final ValueChanged<CashMovement> onDeleteMovement;

  @override
  State<CashContent> createState() => _CashContentState();
}

class _CashContentState extends State<CashContent> {
  String _period = 'Tout';
  String _method = 'Tous';

  bool _isCashPayment(String method) {
    final value = _normalizeAssistantQuery(method);
    return value == 'especes' || value == 'cash';
  }

  Future<void> _reconcileCash() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final todayCash = _combinedMovements().where((movement) {
      final date = movement.date;
      return !date.isBefore(today) &&
          date.isBefore(today.add(const Duration(days: 1))) &&
          _isCashPayment(movement.paymentMethod);
    });
    final inflows = todayCash
        .where((movement) => movement.direction == 'Entrée')
        .fold<double>(0, (sum, movement) => sum + movement.amount);
    final outflows = todayCash
        .where((movement) => movement.direction == 'Sortie')
        .fold<double>(0, (sum, movement) => sum + movement.amount);
    final openingController = TextEditingController();
    final countedController = TextEditingController();
    double read(TextEditingController controller) =>
        double.tryParse(controller.text.trim().replaceAll(',', '.')) ?? 0;
    final result = await showDialog<double>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, refresh) {
          final expected = read(openingController) + inflows - outflows;
          final counted = read(countedController);
          final variance = counted - expected;
          return AlertDialog(
            title: Text(_tr('Clôture guidée de caisse', 'Guided cash closing')),
            content: SizedBox(
              width: _dialogWidth(dialogContext, 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _tr(
                      'Comparaison des mouvements espèces enregistrés aujourd’hui avec l’argent réellement compté.',
                      'Compare today’s recorded cash movements with the cash physically counted.',
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: openingController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) => refresh(() {}),
                    decoration: InputDecoration(
                      labelText: _tr(
                        'Espèces au début de journée',
                        'Opening cash',
                      ),
                      helperText: _tr(
                        'Saisis 0 si la caisse était vide.',
                        'Enter 0 if the drawer started empty.',
                      ),
                      suffixText: _activeCurrencyCode,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: countedController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) => refresh(() {}),
                    decoration: InputDecoration(
                      labelText: _tr(
                        'Espèces réellement comptées',
                        'Cash counted',
                      ),
                      suffixText: _activeCurrencyCode,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    _tr(
                      'Entrées en espèces : ${_money(inflows)}',
                      'Cash received: ${_money(inflows)}',
                    ),
                  ),
                  Text(
                    _tr(
                      'Sorties en espèces : ${_money(outflows)}',
                      'Cash paid out: ${_money(outflows)}',
                    ),
                  ),
                  const Divider(height: 20),
                  Text(
                    _tr(
                      'Solde attendu : ${_money(expected)}',
                      'Expected cash: ${_money(expected)}',
                    ),
                  ),
                  Text(
                    _tr(
                      'Écart : ${_money(variance)}',
                      'Difference: ${_money(variance)}',
                    ),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: variance.abs() < 0.5
                          ? teal
                          : const Color(0xFFB84A52),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _tr(
                      'Cette vérification n’ajoute ni ne modifie aucun mouvement.',
                      'This check does not add or change any cash movement.',
                    ),
                    style: const TextStyle(color: Colors.black54, fontSize: 12),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(_tr('Fermer', 'Close')),
              ),
              FilledButton(
                onPressed:
                    openingController.text.trim().isEmpty ||
                        countedController.text.trim().isEmpty
                    ? null
                    : () => Navigator.pop(dialogContext, variance),
                child: Text(_tr('Terminer la vérification', 'Finish check')),
              ),
            ],
          );
        },
      ),
    );
    openingController.dispose();
    countedController.dispose();
    if (result != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.abs() < 0.5
                ? _tr('Caisse équilibrée.', 'Cash is balanced.')
                : _tr(
                    'Vérifie l’écart de ${_money(result)} avant de clôturer.',
                    'Review the ${_money(result)} difference before closing.',
                  ),
          ),
        ),
      );
    }
  }

  List<CashMovement> _combinedMovements() {
    final result = <CashMovement>[...widget.movements];
    for (final refund in widget.refunds) {
      if (refund.cashRefund > 0) {
        result.add(
          CashMovement(
            description:
                '${_tr('Remboursement', 'Refund')} • ${refund.receiptNumber}',
            direction: 'Sortie',
            amount: refund.cashRefund,
            paymentMethod: refund.paymentMethod,
            date: refund.date,
            isAutomatic: true,
          ),
        );
      }
    }
    final salesByReceipt = <String, List<SaleRecord>>{};
    for (final sale in widget.sales) {
      salesByReceipt.putIfAbsent(sale.receiptNumber, () => []).add(sale);
    }
    for (final entry in salesByReceipt.entries) {
      final receiptSales = entry.value;
      // Valeur figée à la création de la vente : les paiements ultérieurs
      // apparaissent séparément et ne sont donc jamais comptés deux fois.
      final initialReceived = receiptSales.fold<double>(
        0,
        (sum, sale) => sum + (sale.initialReceived ?? 0),
      );
      if (initialReceived > 0) {
        final firstSale = receiptSales.reduce(
          (a, b) => a.date.isBefore(b.date) ? a : b,
        );
        result.add(
          CashMovement(
            description:
                '${_tr('Encaissement initial', 'Initial payment')} • ${entry.key}',
            direction: 'Entrée',
            amount: initialReceived,
            paymentMethod: firstSale.paymentMethod,
            date: firstSale.date,
            isAutomatic: true,
          ),
        );
      }
    }
    for (final payment in widget.payments) {
      result.add(
        CashMovement(
          description:
              '${_tr('Paiement client', 'Customer payment')} • ${payment.receiptNumber}',
          direction: 'Entrée',
          amount: payment.amount,
          paymentMethod: payment.paymentMethod,
          date: payment.date,
          isAutomatic: true,
        ),
      );
    }
    for (final purchase in widget.purchases) {
      if (purchase.paymentMethod == 'Crédit fournisseur' ||
          purchase.paymentMethod == 'Non précisé')
        continue;
      result.add(
        CashMovement(
          description: '${_tr('Achat', 'Purchase')} • ${purchase.product.name}',
          direction: 'Sortie',
          amount: purchase.totalCost,
          paymentMethod: purchase.paymentMethod,
          date: purchase.date,
          isAutomatic: true,
        ),
      );
    }
    for (final expense in widget.expenses) {
      result.add(
        CashMovement(
          description: '${_tr('Dépense', 'Expense')} • ${expense.title}',
          direction: 'Sortie',
          amount: expense.amount,
          paymentMethod: expense.paymentMethod,
          date: expense.date,
          isAutomatic: true,
        ),
      );
    }
    result.sort((a, b) => b.date.compareTo(a.date));
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final allMovements = _combinedMovements();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final start = switch (_period) {
      'Aujourd’hui' => today,
      '7 derniers jours' => today.subtract(const Duration(days: 6)),
      'Ce mois' => DateTime(now.year, now.month, 1),
      _ => null,
    };
    final visibleMovements = allMovements.where((item) {
      final matchesPeriod = start == null || !item.date.isBefore(start);
      final matchesMethod = _method == 'Tous' || item.paymentMethod == _method;
      return matchesPeriod && matchesMethod;
    }).toList();
    final incoming = visibleMovements
        .where((item) => item.direction == 'Entrée')
        .fold<double>(0, (sum, item) => sum + item.amount);
    final outgoing = visibleMovements
        .where((item) => item.direction == 'Sortie')
        .fold<double>(0, (sum, item) => sum + item.amount);
    final balance = incoming - outgoing;
    final methods =
        allMovements.map((item) => item.paymentMethod).toSet().toList()..sort();
    methods.insert(0, 'Tous');
    return ListView(
      padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 600 ? 16 : 26),
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final action = Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _reconcileCash,
                  icon: const Icon(Icons.fact_check_outlined),
                  label: Text(_tr('Clôturer la caisse', 'Close cash register')),
                ),
                FilledButton.icon(
                  onPressed: widget.onAddMovement,
                  icon: const Icon(Icons.add),
                  label: Text(_tr('Nouveau mouvement', 'New movement')),
                ),
              ],
            );
            return _BizPageHero(
              title: _tr('Journal de caisse', 'Cash journal'),
              subtitle: _tr(
                'Une vue claire des encaissements, des paiements et du solde de la période.',
                'A clear view of receipts, payments and the period balance.',
              ),
              icon: Icons.account_balance_wallet_rounded,
              action: action,
            );
          },
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF172B70), Color(0xFF263FA5)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(22),
            boxShadow: const [
              BoxShadow(
                color: Color(0x22172B70),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 560;
              final details = Wrap(
                spacing: 22,
                runSpacing: 14,
                children: [
                  _CashOverviewValue(
                    label: _tr('Entrées', 'Money in'),
                    value: _money(incoming),
                    icon: Icons.south_west_rounded,
                    color: const Color(0xFF61D6BE),
                  ),
                  _CashOverviewValue(
                    label: _tr('Sorties', 'Money out'),
                    value: _money(outgoing),
                    icon: Icons.north_east_rounded,
                    color: const Color(0xFFFFC16E),
                  ),
                ],
              );
              final balanceValue = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _tr('SOLDE DE LA PÉRIODE', 'PERIOD BALANCE'),
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    _money(balance),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              );
              return narrow
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        balanceValue,
                        const SizedBox(height: 18),
                        details,
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(child: balanceValue),
                        const SizedBox(width: 20),
                        details,
                      ],
                    );
            },
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: 230,
              child: SummaryCard(
                title: _tr('Entrées enregistrées', 'Recorded inflows'),
                value: _money(incoming),
                icon: Icons.south_west_rounded,
                color: teal,
              ),
            ),
            SizedBox(
              width: 230,
              child: SummaryCard(
                title: _tr('Sorties enregistrées', 'Recorded outflows'),
                value: _money(outgoing),
                icon: Icons.north_east_rounded,
                color: const Color(0xFFD88931),
              ),
            ),
            SizedBox(
              width: 230,
              child: SummaryCard(
                title: _tr('Solde des mouvements', 'Movement balance'),
                value: _money(balance),
                icon: Icons.account_balance_wallet_outlined,
                color: balance < 0 ? const Color(0xFFB84A52) : navy,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Card(
          color: const Color(0xFFEFF3FF),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, color: navy),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _tr(
                      'Les ventes créées après cette mise à jour, les paiements clients, achats payés, dépenses et remboursements sont repris automatiquement. Les anciens encaissements initiaux et les achats sans mode de paiement ne peuvent pas être reconstruits; les achats à crédit fournisseur sont exclus jusqu’à leur paiement. Utilise « Nouveau mouvement » uniquement pour les paiements non enregistrés ailleurs.',
                      'New sales, customer payments, paid purchases, expenses and refunds are included automatically. Older opening payments and purchases without a payment method cannot be reconstructed; supplier-credit purchases are excluded until paid. Use “New movement” only for payments not recorded elsewhere.',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: Text(
                _tr('Journal de caisse', 'Cash journal'),
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: ink,
                ),
              ),
            ),
            Chip(
              label: Text(
                _tr(
                  '${visibleMovements.length} mouvement(s)',
                  '${visibleMovements.length} movement(s)',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            SizedBox(
              width: 210,
              child: DropdownButtonFormField<String>(
                value: _period,
                decoration: InputDecoration(
                  labelText: _tr('Période', 'Period'),
                  border: const OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
                items:
                    const ['Tout', 'Aujourd’hui', '7 derniers jours', 'Ce mois']
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(_periodLabel(value)),
                          ),
                        )
                        .toList(),
                onChanged: (value) => setState(() => _period = value ?? 'Tout'),
              ),
            ),
            SizedBox(
              width: 210,
              child: DropdownButtonFormField<String>(
                value: _method,
                decoration: InputDecoration(
                  labelText: _tr('Mode de paiement', 'Payment method'),
                  border: const OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
                items: methods
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: Text(_paymentMethodLabel(value)),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _method = value ?? 'Tous'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (allMovements.isEmpty)
          Card(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                children: [
                  const Icon(
                    Icons.account_balance_wallet_outlined,
                    size: 42,
                    color: navy,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _tr(
                      'Aucun mouvement de caisse enregistré.',
                      'No cash movement has been recorded.',
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: widget.onAddMovement,
                    icon: const Icon(Icons.add),
                    label: Text(
                      _tr('Enregistrer un mouvement', 'Record a movement'),
                    ),
                  ),
                ],
              ),
            ),
          )
        else if (visibleMovements.isEmpty)
          Card(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                _tr(
                  'Aucun mouvement ne correspond à ces filtres.',
                  'No movements match these filters.',
                ),
              ),
            ),
          )
        else
          ...visibleMovements.map((item) {
            final isIncoming = item.direction == 'Entrée';
            final color = isIncoming ? teal : const Color(0xFFD88931);
            return Card(
              color: Colors.white,
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: color.withValues(alpha: 0.10),
                  child: Icon(
                    isIncoming
                        ? Icons.south_west_rounded
                        : Icons.north_east_rounded,
                    color: color,
                  ),
                ),
                title: Text(
                  item.description,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  '${_tr(item.direction, item.direction == 'Entrée' ? 'Income' : 'Outflow')} • ${_paymentMethodLabel(item.paymentMethod)} • ${_date(item.date)}',
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${isIncoming ? '+' : '−'}${_money(item.amount)}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                    if (!item.isAutomatic)
                      PopupMenuButton<String>(
                        tooltip: _tr(
                          'Actions sur le mouvement',
                          'Movement actions',
                        ),
                        onSelected: (_) {
                          setState(() => _method = 'Tous');
                          widget.onDeleteMovement(item);
                        },
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            value: 'delete',
                            child: Text(_tr('Supprimer', 'Delete')),
                          ),
                        ],
                        icon: const Icon(Icons.more_horiz),
                        padding: EdgeInsets.zero,
                      ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }
}

class AddCashMovementDialog extends StatefulWidget {
  const AddCashMovementDialog({super.key});

  @override
  State<AddCashMovementDialog> createState() => _AddCashMovementDialogState();
}

class _AddCashMovementDialogState extends State<AddCashMovementDialog> {
  final formKey = GlobalKey<FormState>();
  final description = TextEditingController();
  final amount = TextEditingController();
  String direction = 'Entrée';
  String paymentMethod = 'Espèces';

  @override
  void dispose() {
    description.dispose();
    amount.dispose();
    super.dispose();
  }

  void _save() {
    if (!formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      CashMovement(
        description: description.text.trim(),
        direction: direction,
        amount: double.parse(amount.text.trim().replaceAll(',', '.')),
        paymentMethod: paymentMethod,
        date: DateTime.now(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(_tr('Nouveau mouvement de caisse', 'New cash movement')),
    content: SizedBox(
      width: _dialogWidth(context, 460),
      child: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: description,
              autofocus: true,
              validator: (value) => value == null || value.trim().isEmpty
                  ? _tr(
                      'Indique le motif du mouvement.',
                      'Enter a reason for this movement.',
                    )
                  : null,
              decoration: InputDecoration(
                labelText: _tr('Motif', 'Reason'),
                hintText: _tr(
                  'Ex. : apport initial, retrait, autre recette',
                  'E.g. opening cash, withdrawal, other income',
                ),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: direction,
              decoration: InputDecoration(
                labelText: _tr('Type', 'Type'),
                border: const OutlineInputBorder(),
              ),
              items: const ['Entrée', 'Sortie']
                  .map(
                    (value) => DropdownMenuItem(
                      value: value,
                      child: Text(
                        _tr(value, value == 'Entrée' ? 'Income' : 'Outflow'),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (value) =>
                  setState(() => direction = value ?? direction),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              validator: (value) {
                final parsed = double.tryParse(
                  (value ?? '').trim().replaceAll(',', '.'),
                );
                return parsed == null || parsed <= 0
                    ? _tr(
                        'Saisis un montant supérieur à zéro.',
                        'Enter an amount greater than zero.',
                      )
                    : null;
              },
              decoration: InputDecoration(
                labelText: 'Montant ($_currencyLabel)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: paymentMethod,
              decoration: InputDecoration(
                labelText: _tr('Mode', 'Payment method'),
                border: const OutlineInputBorder(),
              ),
              items: const ['Espèces', 'Mobile Money', 'Banque', 'Autre']
                  .map(
                    (value) => DropdownMenuItem(
                      value: value,
                      child: Text(_paymentMethodLabel(value)),
                    ),
                  )
                  .toList(),
              onChanged: (value) =>
                  setState(() => paymentMethod = value ?? paymentMethod),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(_tr('Annuler', 'Cancel')),
      ),
      FilledButton(onPressed: _save, child: Text(_tr('Enregistrer', 'Save'))),
    ],
  );
}

class ExpenseRecord {
  ExpenseRecord({
    String? recordId,
    required this.title,
    required this.category,
    required this.amount,
    required this.paymentMethod,
    required this.date,
    required this.note,
  }) : recordId = recordId ?? _newRecordId();
  final String recordId;
  final String title;
  final String category;
  final double amount;
  final String paymentMethod;
  final DateTime date;
  final String note;
  Map<String, dynamic> toJson() => {
    'recordId': recordId,
    'title': title,
    'category': category,
    'amount': amount,
    'paymentMethod': paymentMethod,
    'date': date.toIso8601String(),
    'note': note,
  };
  factory ExpenseRecord.fromJson(Map<String, dynamic> json) => ExpenseRecord(
    recordId: json['recordId'] as String?,
    title: json['title'] as String,
    category: json['category'] as String,
    amount: (json['amount'] as num).toDouble(),
    paymentMethod: json['paymentMethod'] as String,
    date: DateTime.parse(json['date'] as String),
    note: json['note'] as String,
  );
}

class AddExpenseDialog extends StatefulWidget {
  const AddExpenseDialog({super.key});
  @override
  State<AddExpenseDialog> createState() => _AddExpenseDialogState();
}

class _AddExpenseDialogState extends State<AddExpenseDialog> {
  final formKey = GlobalKey<FormState>();
  final title = TextEditingController();
  final amount = TextEditingController();
  final note = TextEditingController();
  String category = 'Loyer';
  String paymentMethod = 'Espèces';
  @override
  void dispose() {
    title.dispose();
    amount.dispose();
    note.dispose();
    super.dispose();
  }

  void _save() {
    if (!formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      ExpenseRecord(
        title: title.text.trim(),
        category: category,
        amount: double.parse(amount.text.trim().replaceAll(',', '.')),
        paymentMethod: paymentMethod,
        date: DateTime.now(),
        note: note.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Enregistrer une dépense'),
    content: SizedBox(
      width: _dialogWidth(context, 460),
      child: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: title,
              validator: (v) => v == null || v.trim().isEmpty
                  ? 'Indique le motif de la dépense.'
                  : null,
              decoration: const InputDecoration(
                labelText: 'Motif',
                hintText: 'Ex. : loyer, électricité',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: category,
              decoration: const InputDecoration(
                labelText: 'Catégorie',
                border: OutlineInputBorder(),
              ),
              items: const [
                'Loyer',
                'Électricité / eau',
                'Salaire',
                'Communication',
                'Entretien',
                'Transport',
                'Frais bancaires',
                'Autre',
              ].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
              onChanged: (v) => setState(() => category = v ?? category),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              validator: (v) {
                final n = double.tryParse(
                  (v ?? '').trim().replaceAll(',', '.'),
                );
                return n == null || n <= 0
                    ? 'Saisis un montant supérieur à zéro.'
                    : null;
              },
              decoration: InputDecoration(
                labelText: 'Montant payé ($_currencyLabel)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: paymentMethod,
              decoration: const InputDecoration(
                labelText: 'Mode de paiement',
                border: OutlineInputBorder(),
              ),
              items: const [
                'Espèces',
                'Mobile Money',
                'Banque',
              ].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
              onChanged: (v) =>
                  setState(() => paymentMethod = v ?? paymentMethod),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: note,
              decoration: const InputDecoration(
                labelText: 'Note (facultative)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Annuler'),
      ),
      FilledButton(onPressed: _save, child: const Text('Enregistrer')),
    ],
  );
}

class ExpenseContent extends StatelessWidget {
  const ExpenseContent({
    super.key,
    required this.expenses,
    required this.onAddExpense,
  });
  final List<ExpenseRecord> expenses;
  final VoidCallback onAddExpense;
  @override
  Widget build(BuildContext context) {
    final total = expenses.fold(0.0, (sum, item) => sum + item.amount);
    final byCategory = <String, double>{};
    for (final item in expenses) {
      byCategory.update(
        item.category,
        (value) => value + item.amount,
        ifAbsent: () => item.amount,
      );
    }
    final categoryTotals = byCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return ListView(
      padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 600 ? 16 : 26),
      children: [
        _BizPageHero(
          title: _tr('Dépenses du commerce', 'Business expenses'),
          subtitle: _tr(
            'Suis les sorties d’argent et leur répartition.',
            'Track outgoing money and see where it goes.',
          ),
          icon: Icons.receipt_long_rounded,
          action: FilledButton.icon(
            onPressed: onAddExpense,
            icon: const Icon(Icons.add),
            label: Text(_tr('Nouvelle dépense', 'New expense')),
          ),
        ),
        const SizedBox(height: 18),
        Card(
          color: Colors.white,
          child: ListTile(
            leading: const Icon(Icons.payments_outlined, color: teal),
            title: Text(
              _tr('Total des dépenses enregistrées', 'Total expenses recorded'),
            ),
            trailing: Text(
              _money(total),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ),
        ),
        if (categoryTotals.isNotEmpty) ...[
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _tr('Répartition par catégorie', 'Expenses by category'),
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: navy,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...categoryTotals.map(
                    (entry) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  entry.key,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Text(
                                _money(entry.value),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: ink,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: LinearProgressIndicator(
                              value: total == 0
                                  ? 0.0
                                  : (entry.value / total)
                                        .clamp(0.0, 1.0)
                                        .toDouble(),
                              minHeight: 7,
                              backgroundColor: const Color(0xFFE8EAFE),
                              color: navy,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        if (expenses.isEmpty)
          Card(
            color: Colors.white,
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                _tr(
                  'Aucune dépense enregistrée. Les frais de transport liés aux achats sont déjà saisis dans Achats.',
                  'No expenses recorded. Delivery costs for purchases are already included under Purchases.',
                ),
              ),
            ),
          )
        else
          ...expenses.map(
            (item) => Card(
              color: Colors.white,
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFFFF1E4),
                  child: Icon(
                    Icons.receipt_long_outlined,
                    color: Color(0xFFD88931),
                  ),
                ),
                title: Text(
                  item.title,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  item.category +
                      ' • ' +
                      _date(item.date) +
                      ' • ' +
                      _paymentMethodLabel(item.paymentMethod) +
                      (item.note.isEmpty ? '' : '\n' + item.note),
                ),
                trailing: Text(
                  _money(item.amount),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: ink,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ProfitCostBucket {
  _ProfitCostBucket({required this.start, required this.label});
  final DateTime start;
  final String label;
  double revenue = 0;
  double goodsCost = 0;
  double operatingExpenses = 0;
  double get totalCosts => goodsCost + operatingExpenses;
  double get profit => revenue - totalCosts;
}

class ReportsContent extends StatefulWidget {
  const ReportsContent({
    super.key,
    required this.sales,
    required this.payments,
    required this.purchases,
    required this.expenses,
    required this.refunds,
    required this.products,
    required this.cashMovements,
  });
  final List<SaleRecord> sales;
  final List<PaymentRecord> payments;
  final List<PurchaseRecord> purchases;
  final List<ExpenseRecord> expenses;
  final List<RefundRecord> refunds;
  final List<Product> products;
  final List<CashMovement> cashMovements;

  @override
  State<ReportsContent> createState() => _ReportsContentState();
}

class _ReportsContentState extends State<ReportsContent> {
  String _period = 'Mois';
  String _category = 'Toutes';

  Widget _comparisonRow(
    String label,
    double previous,
    double current, {
    bool higherIsBetter = true,
  }) {
    final difference = current - previous;
    final percent = previous == 0
        ? null
        : difference.abs() / previous.abs() * 100;
    final favorable = higherIsBetter ? difference >= 0 : difference <= 0;
    final changeText = previous == 0
        ? (current == 0 ? '—' : 'Nouveau')
        : '${difference >= 0 ? '+' : ''}${_money(difference)}${percent == null ? '' : ' (${difference >= 0 ? '+' : '-'}${percent.toStringAsFixed(0)} %)'}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            changeText,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: difference == 0
                  ? Colors.black54
                  : favorable
                  ? teal
                  : const Color(0xFFB84A52),
            ),
          ),
        ],
      ),
    );
  }

  List<_ProfitCostBucket> _makeBuckets(DateTime now) {
    final count = _period == 'Mois'
        ? 6
        : _period == 'Trimestre'
        ? 4
        : 5;
    final buckets = <_ProfitCostBucket>[];
    if (_period == 'Mois') {
      for (var offset = count - 1; offset >= 0; offset--) {
        final start = DateTime(now.year, now.month - offset, 1);
        buckets.add(
          _ProfitCostBucket(
            start: start,
            label:
                '${_monthName(start.month)} ${start.year.toString().substring(2)}',
          ),
        );
      }
    } else if (_period == 'Trimestre') {
      final currentQuarterMonth = ((now.month - 1) ~/ 3) * 3 + 1;
      for (var offset = count - 1; offset >= 0; offset--) {
        final start = DateTime(now.year, currentQuarterMonth - offset * 3, 1);
        final quarter = ((start.month - 1) ~/ 3) + 1;
        buckets.add(
          _ProfitCostBucket(
            start: start,
            label: 'T$quarter ${start.year.toString().substring(2)}',
          ),
        );
      }
    } else {
      for (var offset = count - 1; offset >= 0; offset--) {
        final start = DateTime(now.year - offset, 1, 1);
        buckets.add(
          _ProfitCostBucket(start: start, label: start.year.toString()),
        );
      }
    }
    for (var index = 0; index < buckets.length; index++) {
      final bucket = buckets[index];
      final end = index + 1 < buckets.length
          ? buckets[index + 1].start
          : _period == 'Mois'
          ? DateTime(bucket.start.year, bucket.start.month + 1, 1)
          : _period == 'Trimestre'
          ? DateTime(bucket.start.year, bucket.start.month + 3, 1)
          : DateTime(bucket.start.year + 1, 1, 1);
      for (final sale in widget.sales) {
        if (_category != 'Toutes' && sale.product.category != _category)
          continue;
        if (!sale.date.isBefore(bucket.start) && sale.date.isBefore(end)) {
          bucket.revenue += sale.total;
          bucket.goodsCost += sale.stockQuantity * sale.product.purchasePrice;
        }
      }
      for (final expense in widget.expenses) {
        // Les frais généraux ne sont pas encore rattachés à un produit précis.
        if (_category != 'Toutes') continue;
        if (!expense.date.isBefore(bucket.start) &&
            expense.date.isBefore(end)) {
          bucket.operatingExpenses += expense.amount;
        }
      }
    }
    return buckets;
  }

  String _monthName(int month) => (_activeLanguageCode == 'en'
      ? const [
          'Jan',
          'Feb',
          'Mar',
          'Apr',
          'May',
          'Jun',
          'Jul',
          'Aug',
          'Sep',
          'Oct',
          'Nov',
          'Dec',
        ]
      : const [
          'Jan',
          'Fév',
          'Mar',
          'Avr',
          'Mai',
          'Juin',
          'Juil',
          'Aoû',
          'Sep',
          'Oct',
          'Nov',
          'Déc',
        ])[month - 1];

  DateTime _bucketEnd(_ProfitCostBucket bucket) => _period == 'Mois'
      ? DateTime(bucket.start.year, bucket.start.month + 1, 1)
      : _period == 'Trimestre'
      ? DateTime(bucket.start.year, bucket.start.month + 3, 1)
      : DateTime(bucket.start.year + 1, 1, 1);

  List<_CashFlowPoint> _cashFlow(List<_ProfitCostBucket> buckets) {
    return buckets.map((bucket) {
      final end = _bucketEnd(bucket);
      bool inPeriod(DateTime date) =>
          !date.isBefore(bucket.start) && date.isBefore(end);
      var incoming = 0.0;
      var outgoing = 0.0;
      for (final sale in widget.sales.where((sale) => inPeriod(sale.date))) {
        incoming += sale.initialReceived ?? 0;
      }
      for (final payment in widget.payments.where(
        (item) => inPeriod(item.date),
      )) {
        incoming += payment.amount;
      }
      for (final refund in widget.refunds.where(
        (item) => inPeriod(item.date),
      )) {
        outgoing += refund.cashRefund;
      }
      for (final purchase in widget.purchases.where(
        (item) => inPeriod(item.date),
      )) {
        if (purchase.paymentMethod != 'Crédit fournisseur' &&
            purchase.paymentMethod != 'Non précisé')
          outgoing += purchase.totalCost;
      }
      for (final expense in widget.expenses.where(
        (item) => inPeriod(item.date),
      )) {
        outgoing += expense.amount;
      }
      for (final movement in widget.cashMovements.where(
        (item) => inPeriod(item.date),
      )) {
        if (movement.direction == 'Entrée') {
          incoming += movement.amount;
        } else {
          outgoing += movement.amount;
        }
      }
      return _CashFlowPoint(
        label: bucket.label,
        incoming: incoming,
        outgoing: outgoing,
      );
    }).toList();
  }

  Future<void> _exportPdf(
    List<_ProfitCostBucket> buckets, {
    bool share = false,
  }) async {
    final document = pw.Document();
    final totalRevenue = buckets.fold(
      0.0,
      (sum, bucket) => sum + bucket.revenue,
    );
    final totalCost = buckets.fold(
      0.0,
      (sum, bucket) => sum + bucket.totalCosts,
    );
    final totalProfit = buckets.fold(0.0, (sum, bucket) => sum + bucket.profit);
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (_) => [
          pw.Text(
            'BizGestion — Rapport de profits et coûts',
            style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            'Période : $_period • Catégorie : $_category • Généré le ${_date(DateTime.now())}',
          ),
          pw.SizedBox(height: 18),
          pw.Text('Chiffre d’affaires : ${_money(totalRevenue)}'),
          pw.Text('Coûts estimés : ${_money(totalCost)}'),
          pw.Text('Bénéfice net estimé : ${_money(totalProfit)}'),
          pw.SizedBox(height: 18),
          pw.TableHelper.fromTextArray(
            headers: ['Période', 'Ventes', 'Coûts', 'Bénéfice net'],
            data: buckets
                .map(
                  (bucket) => [
                    bucket.label,
                    _money(bucket.revenue),
                    _money(bucket.totalCosts),
                    _money(bucket.profit),
                  ],
                )
                .toList(),
          ),
          pw.SizedBox(height: 12),
          pw.Text(
            'Le coût des produits vendus utilise leur coût d’achat enregistré. Les dépenses sont celles saisies séparément dans BizGestion.',
          ),
        ],
      ),
    );
    final bytes = await document.save();
    if (share && (await Printing.info()).canShare) {
      await Printing.sharePdf(
        bytes: bytes,
        filename:
            'bizgestion-rapport-${DateTime.now().millisecondsSinceEpoch}.pdf',
        subject: _tr('Rapport BizGestion', 'BizGestion report'),
      );
    } else {
      await Printing.layoutPdf(onLayout: (_) async => bytes);
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final buckets = _makeBuckets(now);
    final revenue = buckets.fold(0.0, (sum, bucket) => sum + bucket.revenue);
    final goodsCost = buckets.fold(
      0.0,
      (sum, bucket) => sum + bucket.goodsCost,
    );
    final expenses = buckets.fold(
      0.0,
      (sum, bucket) => sum + bucket.operatingExpenses,
    );
    final net = revenue - goodsCost - expenses;
    final received = widget.sales.fold(0.0, (sum, sale) => sum + sale.received);
    final credit = widget.sales.fold(0.0, (sum, sale) => sum + sale.balance);
    final returnedValue = widget.refunds.fold(
      0.0,
      (sum, item) => sum + item.value,
    );
    final cashRefunds = widget.refunds.fold(
      0.0,
      (sum, item) => sum + item.cashRefund,
    );
    final purchaseCosts = widget.purchases.fold(
      0.0,
      (sum, purchase) => sum + purchase.totalCost,
    );
    final grossMargin = revenue - goodsCost;
    final categories =
        widget.sales.map((sale) => sale.product.category).toSet().toList()
          ..sort();
    final latestBucket = buckets.isEmpty ? null : buckets.last;
    final previousBucket = buckets.length < 2
        ? null
        : buckets[buckets.length - 2];
    final categoryStats = categories.map((category) {
      var categoryRevenue = 0.0;
      var categoryCost = 0.0;
      if (buckets.isNotEmpty) {
        final start = buckets.first.start;
        final last = buckets.last;
        final end = _period == 'Mois'
            ? DateTime(last.start.year, last.start.month + 1, 1)
            : _period == 'Trimestre'
            ? DateTime(last.start.year, last.start.month + 3, 1)
            : DateTime(last.start.year + 1, 1, 1);
        for (final sale in widget.sales.where(
          (sale) =>
              sale.product.category == category &&
              !sale.date.isBefore(start) &&
              sale.date.isBefore(end),
        )) {
          categoryRevenue += sale.total;
          categoryCost += sale.stockQuantity * sale.product.purchasePrice;
        }
      }
      return _CategoryReport(
        category: category,
        revenue: categoryRevenue,
        cost: categoryCost,
      );
    }).toList()..sort((a, b) => b.revenue.compareTo(a.revenue));
    final reportStart = buckets.isEmpty
        ? DateTime(now.year, now.month, 1)
        : buckets.first.start;
    final reportEnd = buckets.isEmpty
        ? DateTime(now.year, now.month + 1, 1)
        : _bucketEnd(buckets.last);
    final expensesByCategory = <String, double>{};
    if (_category == 'Toutes') {
      for (final expense in widget.expenses.where(
        (item) =>
            !item.date.isBefore(reportStart) && item.date.isBefore(reportEnd),
      )) {
        expensesByCategory.update(
          expense.category,
          (value) => value + expense.amount,
          ifAbsent: () => expense.amount,
        );
      }
    }
    final expenseChartEntries = expensesByCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final expenseBarEntries = expenseChartEntries
        .take(3)
        .map((entry) => _LabeledValue(entry.key, entry.value))
        .toList();
    if (expenseChartEntries.length > 3) {
      expenseBarEntries.add(
        _LabeledValue(
          'Autres catégories',
          expenseChartEntries
              .skip(3)
              .fold<double>(0, (sum, entry) => sum + entry.value),
        ),
      );
    }
    final stockChartEntries =
        widget.products
            .map(
              (product) =>
                  MapEntry(product, product.quantity * product.purchasePrice),
            )
            .where((entry) => entry.value > 0)
            .toList()
          ..sort((a, b) => b.value.compareTo(a.value));
    final cashFlowPoints = _cashFlow(buckets);

    return ListView(
      padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 600 ? 16 : 26),
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final actions = Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _exportPdf(buckets, share: true),
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: Text(
                    _tr(
                      'Partager / exporter le rapport',
                      'Share / export report',
                    ),
                  ),
                ),
              ],
            );
            return _BizPageHero(
              title: _tr('Analyse de l’activité', 'Business performance'),
              subtitle: _tr(
                'Compare tes ventes, le coût du stock vendu, les dépenses et le bénéfice sur une même période.',
                'Compare sales, cost of goods sold, expenses and profit over the same period.',
              ),
              icon: Icons.query_stats_rounded,
              action: actions,
            );
          },
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF172B70), Color(0xFF263FA5)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(22),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 620;
              final profit = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _category == 'Toutes'
                        ? _tr('BÉNÉFICE NET ESTIMÉ', 'ESTIMATED NET PROFIT')
                        : _tr('MARGE ESTIMÉE', 'ESTIMATED MARGIN'),
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    _money(net),
                    style: TextStyle(
                      color: net < 0 ? const Color(0xFFFFB2A9) : Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    _tr(
                      'Marge brute ${_money(grossMargin)} moins dépenses ${_money(expenses)}',
                      'Gross margin ${_money(grossMargin)} less expenses ${_money(expenses)}',
                    ),
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              );
              final breakdown = Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _ReportBreakdownValue(
                    label: _tr('Ventes', 'Sales'),
                    value: _money(revenue),
                  ),
                  _ReportBreakdownValue(
                    label: _tr('Coût vendu', 'Goods cost'),
                    value: '− ${_money(goodsCost)}',
                  ),
                  _ReportBreakdownValue(
                    label: _tr('Dépenses', 'Expenses'),
                    value: '− ${_money(expenses)}',
                  ),
                ],
              );
              return narrow
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [profit, const SizedBox(height: 18), breakdown],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(flex: 4, child: profit),
                        const SizedBox(width: 16),
                        Expanded(flex: 5, child: breakdown),
                      ],
                    );
            },
          ),
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) => GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: constraints.maxWidth > 850
                ? 4
                : constraints.maxWidth > 520
                ? 2
                : 1,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: constraints.maxWidth > 520 ? 1.7 : 2.8,
            children: [
              SummaryCard(
                title: _tr('Chiffre d’affaires', 'Revenue'),
                value: _money(revenue),
                icon: Icons.payments_outlined,
                color: teal,
              ),
              SummaryCard(
                title: _tr('Coût des produits vendus', 'Cost of goods sold'),
                value: _money(goodsCost),
                icon: Icons.inventory_2_outlined,
                color: navy,
              ),
              SummaryCard(
                title: _tr('Marge brute estimée', 'Estimated gross margin'),
                value: _money(grossMargin),
                icon: Icons.trending_up_outlined,
                color: teal,
              ),
              SummaryCard(
                title: _tr('Dépenses enregistrées', 'Expenses recorded'),
                value: _money(expenses),
                icon: Icons.receipt_long_outlined,
                color: const Color(0xFFD88931),
              ),
              SummaryCard(
                title: _category == 'Toutes'
                    ? _tr('Bénéfice net estimé', 'Estimated net profit')
                    : _tr('Marge estimée', 'Estimated margin'),
                value: _money(net),
                icon: Icons.trending_up_outlined,
                color: net < 0 ? const Color(0xFFB84A52) : teal,
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Card(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: Color(0xFFE8EDEF)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final filterControls = Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SegmentedButton<String>(
                          segments: [
                            ButtonSegment(
                              value: 'Mois',
                              label: Text(_tr('Mois', 'Month')),
                            ),
                            ButtonSegment(
                              value: 'Trimestre',
                              label: Text(_tr('Trimestre', 'Quarter')),
                            ),
                            ButtonSegment(
                              value: 'Année',
                              label: Text(_tr('Année', 'Year')),
                            ),
                          ],
                          selected: {_period},
                          onSelectionChanged: (selection) =>
                              setState(() => _period = selection.first),
                          showSelectedIcon: false,
                        ),
                        SizedBox(
                          width: constraints.maxWidth < 600 ? 200 : 220,
                          child: DropdownButtonFormField<String>(
                            value: _category,
                            decoration: InputDecoration(
                              labelText: _tr('Catégorie', 'Category'),
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                            ),
                            items: ['Toutes', ...categories]
                                .map(
                                  (category) => DropdownMenuItem(
                                    value: category,
                                    child: Text(
                                      category == 'Toutes'
                                          ? _tr('Toutes', 'All categories')
                                          : _categoryLabel(category),
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) =>
                                setState(() => _category = value ?? 'Toutes'),
                          ),
                        ),
                      ],
                    );
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _tr(
                            'Évolution des profits et des coûts',
                            'Profit and cost trends',
                          ),
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.bold,
                            color: ink,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _category == 'Toutes'
                              ? _tr(
                                  'Comparaison des ventes, des coûts et du bénéfice net estimé.',
                                  'Comparison of sales, costs and estimated net profit.',
                                )
                              : '${_tr('Analyse des ventes et de la marge pour ', 'Sales and margin analysis for ')}${_categoryLabel(_category)}.',
                          style: const TextStyle(color: Colors.black54),
                        ),
                        const SizedBox(height: 14),
                        filterControls,
                      ],
                    );
                  },
                ),
                const SizedBox(height: 18),
                SizedBox(
                  height: 220,
                  child: _ProfitCostChart(buckets: buckets),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    _ChartLegend(color: teal, label: _tr('Ventes', 'Sales')),
                    _ChartLegend(
                      color: Color(0xFFD88931),
                      label: _tr('Coûts', 'Costs'),
                    ),
                    _ChartLegend(
                      color: navy,
                      label: _tr('Bénéfice net', 'Net profit'),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                const Divider(),
                const SizedBox(height: 8),
                Text(
                  _tr('Détail par période', 'Period details'),
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: ink,
                  ),
                ),
                const SizedBox(height: 8),
                for (final bucket in buckets.reversed)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      bucket.label,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      '${_tr('Ventes', 'Sales')} ${_money(bucket.revenue)} • ${_tr('Coûts', 'Costs')} ${_money(bucket.totalCosts)}',
                    ),
                    trailing: Text(
                      _money(bucket.profit),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: bucket.profit < 0
                            ? const Color(0xFFB84A52)
                            : teal,
                      ),
                    ),
                  ),
                if (latestBucket != null && previousBucket != null) ...[
                  const Divider(),
                  const SizedBox(height: 8),
                  Text(
                    _tr(
                      'Comparaison avec la période précédente',
                      'Compared with previous period',
                    ),
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: ink,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${previousBucket.label}  →  ${latestBucket.label}',
                    style: const TextStyle(color: Colors.black54),
                  ),
                  _comparisonRow(
                    _tr('Ventes', 'Sales'),
                    previousBucket.revenue,
                    latestBucket.revenue,
                  ),
                  _comparisonRow(
                    _tr('Coûts', 'Costs'),
                    previousBucket.totalCosts,
                    latestBucket.totalCosts,
                    higherIsBetter: false,
                  ),
                  _comparisonRow(
                    _tr('Bénéfice net', 'Net profit'),
                    previousBucket.profit,
                    latestBucket.profit,
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth > 1120
                ? 3
                : constraints.maxWidth > 700
                ? 2
                : 1;
            return GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: columns,
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
              childAspectRatio: columns == 1 ? 1.0 : 1.1,
              children: [
                _ReportChartCard(
                  title: _tr('Dépenses par catégorie', 'Expenses by category'),
                  subtitle: _category == 'Toutes'
                      ? _tr(
                          'Sur la période sélectionnée',
                          'For the selected period',
                        )
                      : _tr(
                          'Choisis « Toutes » pour afficher les dépenses',
                          'Select “All categories” to show expenses',
                        ),
                  icon: Icons.pie_chart_outline,
                  child: _HorizontalValueChart(
                    entries: expenseBarEntries,
                    emptyMessage: _category == 'Toutes'
                        ? _tr(
                            'Aucune dépense sur cette période.',
                            'No expenses for this period.',
                          )
                        : _tr(
                            'Les dépenses générales ne sont pas ventilées par produit.',
                            'General expenses are not allocated to individual products.',
                          ),
                    color: const Color(0xFFD88931),
                  ),
                ),
                _ReportChartCard(
                  title: _tr('Valeur du stock', 'Inventory value'),
                  subtitle: _tr(
                    'Produits classés selon leur coût d’achat actuel',
                    'Products ranked by current purchase cost',
                  ),
                  icon: Icons.inventory_2_outlined,
                  child: _HorizontalValueChart(
                    entries: stockChartEntries
                        .take(4)
                        .map(
                          (entry) => _LabeledValue(entry.key.name, entry.value),
                        )
                        .toList(),
                    emptyMessage: _tr(
                      'Aucun stock valorisable pour le moment.',
                      'No inventory value to report yet.',
                    ),
                    color: navy,
                    amountSuffix:
                        ' • ${_tr('stock actuel', 'current inventory')}',
                  ),
                ),
                _ReportChartCard(
                  title: _tr('Flux de caisse', 'Cash flow'),
                  subtitle: _tr(
                    'Entrées et sorties enregistrées par période',
                    'Recorded inflows and outflows by period',
                  ),
                  icon: Icons.account_balance_wallet_outlined,
                  child: _CashFlowChart(points: cashFlowPoints),
                ),
              ],
            );
          },
        ),
        if (categoryStats.isNotEmpty) ...[
          const SizedBox(height: 18),
          Card(
            color: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: const BorderSide(color: Color(0xFFE8EDEF)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _tr('Résultats par catégorie', 'Results by category'),
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                      color: ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _tr(
                      'Marge brute estimée sur la période sélectionnée.',
                      'Estimated gross margin for the selected period.',
                    ),
                    style: TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 8),
                  for (final item in categoryStats)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const CircleAvatar(
                        backgroundColor: Color(0xFFE2F2F0),
                        child: Icon(Icons.category_outlined, color: teal),
                      ),
                      title: Text(
                        _categoryLabel(item.category),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        '${_tr('Ventes', 'Sales')} ${_money(item.revenue)} • ${_tr('Coût vendu', 'Cost of goods sold')} ${_money(item.cost)}',
                      ),
                      trailing: Text(
                        _money(item.revenue - item.cost),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: item.revenue - item.cost < 0
                              ? const Color(0xFFB84A52)
                              : teal,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, constraints) {
            final summaries = [
              _ReportSummary(
                label: _tr('Encaissements cumulés', 'Total received'),
                value: _money(received),
                icon: Icons.account_balance_wallet_outlined,
                color: teal,
              ),
              _ReportSummary(
                label: _tr('Crédits restants', 'Outstanding credit'),
                value: _money(credit),
                icon: Icons.schedule_outlined,
                color: const Color(0xFFB84A52),
              ),
              _ReportSummary(
                label: _tr(
                  'Achats et frais cumulés',
                  'Purchases and expenses total',
                ),
                value: _money(purchaseCosts),
                icon: Icons.local_shipping_outlined,
                color: const Color(0xFFD88931),
              ),
              _ReportSummary(
                label: _tr('Retours cumulés', 'Total returns'),
                value: _money(returnedValue),
                icon: Icons.assignment_return_outlined,
                color: const Color(0xFF5278B8),
              ),
              _ReportSummary(
                label: _tr('Remboursements cumulés', 'Total refunds'),
                value: _money(cashRefunds),
                icon: Icons.money_off_outlined,
                color: const Color(0xFFB84A52),
              ),
            ];
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: summaries.map((item) {
                final width = constraints.maxWidth > 700
                    ? (constraints.maxWidth - 24) / 3
                    : constraints.maxWidth;
                return SizedBox(
                  width: width,
                  child: Card(
                    color: Colors.white,
                    elevation: 0,
                    child: ListTile(
                      leading: Icon(item.icon, color: item.color),
                      title: Text(item.label),
                      trailing: Text(
                        item.value,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: ink,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
        const SizedBox(height: 12),
        Card(
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              _category == 'Toutes'
                  ? _tr(
                      'Le bénéfice net estimé soustrait du chiffre d’affaires le coût d’achat des produits vendus et les dépenses enregistrées. Les achats de stock sont présentés à part pour ne pas compter deux fois les marchandises encore en stock.',
                      'Estimated net profit subtracts the purchase cost of goods sold and recorded expenses from revenue. Inventory purchases are shown separately to avoid counting goods still in stock twice.',
                    )
                  : _tr(
                      'Le filtre par catégorie montre les ventes et la marge brute des produits de cette catégorie. Les dépenses générales ne sont pas attribuées à une catégorie de produit.',
                      'The category filter shows sales and gross margin for products in that category. General expenses are not assigned to a product category.',
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CategoryReport {
  const _CategoryReport({
    required this.category,
    required this.revenue,
    required this.cost,
  });
  final String category;
  final double revenue;
  final double cost;
}

class _LabeledValue {
  const _LabeledValue(this.label, this.value);
  final String label;
  final double value;
}

class _CashFlowPoint {
  const _CashFlowPoint({
    required this.label,
    required this.incoming,
    required this.outgoing,
  });
  final String label;
  final double incoming;
  final double outgoing;
}

class _ReportChartCard extends StatelessWidget {
  const _ReportChartCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
  });
  final String title;
  final String subtitle;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
    color: Colors.white,
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: const BorderSide(color: Color(0xFFE8EDEF)),
    ),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: navy),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: Colors.black54),
          ),
          const SizedBox(height: 12),
          Expanded(child: child),
        ],
      ),
    ),
  );
}

class _HorizontalValueChart extends StatelessWidget {
  const _HorizontalValueChart({
    required this.entries,
    required this.emptyMessage,
    required this.color,
    this.amountSuffix = '',
  });
  final List<_LabeledValue> entries;
  final String emptyMessage;
  final Color color;
  final String amountSuffix;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty)
      return Center(
        child: Text(
          emptyMessage,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.black54),
        ),
      );
    final maxValue = entries
        .map((item) => item.value)
        .fold<double>(0, (a, b) => a > b ? a : b);
    return Column(
      children: entries.take(4).map((item) {
        final ratio = maxValue <= 0
            ? 0.0
            : (item.value / maxValue).clamp(0.0, 1.0).toDouble();
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${_money(item.value)}$amountSuffix',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: Colors.black54),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: ratio,
                  minHeight: 9,
                  backgroundColor: color.withValues(alpha: 0.1),
                  color: color,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _CashFlowChart extends StatelessWidget {
  const _CashFlowChart({required this.points});
  final List<_CashFlowPoint> points;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty ||
        points.every((item) => item.incoming == 0 && item.outgoing == 0)) {
      return const Center(
        child: Text(
          'Aucun mouvement enregistré sur cette période.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.black54),
        ),
      );
    }
    return Column(
      children: [
        Expanded(
          child: CustomPaint(
            painter: _CashFlowChartPainter(points),
            child: const SizedBox.expand(),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            _ChartLegend(color: teal, label: 'Entrées'),
            SizedBox(width: 12),
            _ChartLegend(color: Color(0xFFD88931), label: 'Sorties'),
          ],
        ),
      ],
    );
  }
}

class _CashFlowChartPainter extends CustomPainter {
  _CashFlowChartPainter(this.points);
  final List<_CashFlowPoint> points;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 4.0;
    const top = 6.0;
    const bottom = 26.0;
    final chartHeight = size.height - top - bottom;
    final chartWidth = size.width - left * 2;
    final maxValue = points
        .expand((item) => [item.incoming, item.outgoing])
        .fold<double>(1, (a, b) => a > b ? a : b);
    final grid = Paint()
      ..color = const Color(0xFFE8EDEF)
      ..strokeWidth = 1;
    for (var line = 0; line <= 3; line++) {
      final y = top + chartHeight * line / 3;
      canvas.drawLine(Offset(left, y), Offset(size.width - left, y), grid);
    }
    final slot = chartWidth / points.length;
    final barWidth = (slot * 0.28).clamp(4.0, 18.0).toDouble();
    for (var index = 0; index < points.length; index++) {
      final center = left + slot * (index + 0.5);
      final point = points[index];
      final incomingHeight = chartHeight * point.incoming / maxValue;
      final outgoingHeight = chartHeight * point.outgoing / maxValue;
      final incomingRect = Rect.fromLTWH(
        center - barWidth - 2,
        top + chartHeight - incomingHeight,
        barWidth,
        incomingHeight,
      );
      final outgoingRect = Rect.fromLTWH(
        center + 2,
        top + chartHeight - outgoingHeight,
        barWidth,
        outgoingHeight,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(incomingRect, const Radius.circular(4)),
        Paint()..color = teal,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(outgoingRect, const Radius.circular(4)),
        Paint()..color = const Color(0xFFD88931),
      );
      final label = TextPainter(
        text: TextSpan(
          text: point.label,
          style: const TextStyle(fontSize: 9, color: Colors.black54),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: slot);
      label.paint(
        canvas,
        Offset(center - label.width / 2, size.height - label.height),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CashFlowChartPainter oldDelegate) =>
      oldDelegate.points != points;
}

class _ReportSummary {
  const _ReportSummary({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
  final String label;
  final String value;
  final IconData icon;
  final Color color;
}

class _ChartLegend extends StatelessWidget {
  const _ChartLegend({required this.color, required this.label});
  final Color color;
  final String label;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 6),
      Text(label, style: const TextStyle(fontSize: 13, color: Colors.black54)),
    ],
  );
}

class _ChartTrendLegend extends StatelessWidget {
  const _ChartTrendLegend({
    required this.color,
    required this.label,
    required this.values,
  });
  final Color color;
  final String label;
  final List<double> values;

  @override
  Widget build(BuildContext context) {
    final current = values.isEmpty ? 0.0 : values.last;
    final previous = values.length < 2 ? current : values[values.length - 2];
    final icon = current > previous
        ? Icons.trending_up_rounded
        : current < previous
        ? Icons.trending_down_rounded
        : Icons.trending_flat_rounded;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(fontSize: 13, color: Colors.black54),
        ),
        const SizedBox(width: 3),
        Icon(icon, size: 17, color: color),
      ],
    );
  }
}

class _ProfitCostChart extends StatelessWidget {
  const _ProfitCostChart({required this.buckets});
  final List<_ProfitCostBucket> buckets;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (buckets.isEmpty)
        return Center(
          child: Text(
            _tr(
              'Aucune donnée à afficher pour cette période.',
              'No data to display for this period.',
            ),
          ),
        );
      return CustomPaint(
        painter: _ProfitCostChartPainter(buckets),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(left: 8, right: 8, bottom: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: buckets
                  .map(
                    (bucket) => SizedBox(
                      width: constraints.maxWidth / buckets.length,
                      child: Text(
                        bucket.label,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xFFB9C9E8),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
      );
    },
  );
}

class _ProfitCostChartPainter extends CustomPainter {
  _ProfitCostChartPainter(this.buckets);
  final List<_ProfitCostBucket> buckets;
  @override
  void paint(Canvas canvas, Size size) {
    const left = 8.0;
    const top = 8.0;
    const bottom = 28.0;
    final chartHeight = size.height - top - bottom;
    final chartWidth = size.width - left * 2;
    final panel = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(16),
    );
    canvas.drawRRect(
      panel,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF101D46), Color(0xFF142B60), Color(0xFF173B77)],
        ).createShader(Offset.zero & size),
    );
    canvas.save();
    canvas.clipRRect(panel);
    var minValue = 0.0;
    var maxValue = 1.0;
    for (final bucket in buckets) {
      if (bucket.revenue > maxValue) maxValue = bucket.revenue;
      if (bucket.totalCosts > maxValue) maxValue = bucket.totalCosts;
      if (bucket.profit > maxValue) maxValue = bucket.profit;
      if (bucket.profit < minValue) minValue = bucket.profit;
    }
    final valueRange = maxValue - minValue;
    final zeroY =
        top + chartHeight - ((0 - minValue) / valueRange) * chartHeight;
    final gridPaint = Paint()
      ..color = const Color(0xFF7892C2).withValues(alpha: 0.22)
      ..strokeWidth = 1;
    for (var line = 0; line <= 4; line++) {
      final y = top + chartHeight * line / 4;
      canvas.drawLine(Offset(left, y), Offset(size.width - left, y), gridPaint);
    }
    canvas.drawLine(
      Offset(left, zeroY),
      Offset(size.width - left, zeroY),
      Paint()
        ..color = const Color(0xFF9BB0D8).withValues(alpha: 0.55)
        ..strokeWidth = 1.3,
    );
    const colors = [Color(0xFF20D6E8), Color(0xFFB57CFF), Color(0xFFFF8C73)];
    final groupWidth = chartWidth / buckets.length;
    final xFor = (int index) => left + groupWidth * (index + 0.5);
    final yFor = (double value) =>
        top + chartHeight - ((value - minValue) / valueRange) * chartHeight;

    final barWidth = (groupWidth * 0.18).clamp(3.0, 18.0).toDouble();
    for (var index = 0; index < buckets.length; index++) {
      final centerX = left + groupWidth * (index + 0.5);
      final amounts = [
        buckets[index].revenue,
        buckets[index].totalCosts,
        buckets[index].profit,
      ];
      for (var series = 0; series < amounts.length; series++) {
        final amount = amounts[series];
        final valueY = yFor(amount);
        final rect = Rect.fromLTRB(
          centerX + (series - 1) * barWidth - barWidth * 0.4,
          amount >= 0 ? valueY : zeroY,
          centerX + (series - 1) * barWidth + barWidth * 0.4,
          amount >= 0 ? zeroY : valueY,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(4)),
          Paint()
            ..color = colors[series].withValues(alpha: 0.82)
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                colors[series].withValues(alpha: 0.95),
                colors[series].withValues(alpha: 0.28),
              ],
            ).createShader(rect),
        );
      }
    }

    final salesPoints = <Offset>[];
    for (var index = 0; index < buckets.length; index++) {
      salesPoints.add(Offset(xFor(index), yFor(buckets[index].revenue)));
    }
    final salesPath = Path()
      ..moveTo(salesPoints.first.dx, salesPoints.first.dy);
    for (final point in salesPoints.skip(1)) {
      salesPath.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(
      salesPath,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.22)
        ..strokeWidth = 9
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(
      salesPath,
      Paint()
        ..color = Colors.white
        ..strokeWidth = 3.2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    for (final point in salesPoints) {
      canvas.drawCircle(point, 5, Paint()..color = const Color(0xFF20D6E8));
      canvas.drawCircle(point, 2.4, Paint()..color = Colors.white);
    }
    if (salesPoints.length > 1) {
      final previous = salesPoints[salesPoints.length - 2];
      final end = salesPoints.last;
      final angle = atan2(end.dy - previous.dy, end.dx - previous.dx);
      const arrowLength = 13.0;
      final arrow = Path()
        ..moveTo(end.dx, end.dy)
        ..lineTo(
          end.dx - arrowLength * cos(angle - 0.48),
          end.dy - arrowLength * sin(angle - 0.48),
        )
        ..moveTo(end.dx, end.dy)
        ..lineTo(
          end.dx - arrowLength * cos(angle + 0.48),
          end.dy - arrowLength * sin(angle + 0.48),
        );
      canvas.drawPath(
        arrow,
        Paint()
          ..color = Colors.white
          ..strokeWidth = 3
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ProfitCostChartPainter oldDelegate) =>
      oldDelegate.buckets != buckets;
}

class CustomerContent extends StatefulWidget {
  const CustomerContent({
    super.key,
    required this.businessName,
    required this.sales,
    required this.payments,
    required this.refunds,
    required this.onCollectPayment,
  });

  final String businessName;
  final List<SaleRecord> sales;
  final List<PaymentRecord> payments;
  final List<RefundRecord> refunds;
  final Future<void> Function(String customerName, double balance)
  onCollectPayment;

  @override
  State<CustomerContent> createState() => _CustomerContentState();
}

class _CustomerContentState extends State<CustomerContent> {
  final search = TextEditingController();
  String filter = 'Tous';

  Future<void> _prepareDebtReminder(
    String name,
    String phone,
    double balance,
  ) async {
    final trimmed = phone.trim();
    if (!trimmed.startsWith('+') && !trimmed.startsWith('00')) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _tr(
              'Ajoute l’indicatif international au numéro du client (ex. +229…) pour préparer le rappel WhatsApp.',
              'Add the customer’s international dialing code (for example +229…) to prepare the WhatsApp reminder.',
            ),
          ),
        ),
      );
      return;
    }
    var internationalNumber = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
    if (trimmed.startsWith('00') && internationalNumber.startsWith('00')) {
      internationalNumber = internationalNumber.substring(2);
    }
    final text = _tr(
      'Bonjour $name, petit rappel concernant le solde de ${_money(balance)} dû à ${widget.businessName}. Si tu as déjà réglé, merci de ne pas tenir compte de ce message. Bonne journée !',
      'Hello $name, a quick reminder about the ${_money(balance)} balance due to ${widget.businessName}. If you have already paid, please ignore this message. Have a nice day!',
    );
    final uri = Uri.https('wa.me', '/$internationalNumber', {'text': text});
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _tr(
              'Impossible d’ouvrir WhatsApp sur cet appareil.',
              'Could not open WhatsApp on this device.',
            ),
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  double _balanceFor(List<SaleRecord> customerSales) =>
      customerSales.fold(0.0, (sum, sale) => sum + sale.balance);

  List<SaleRecord> _customerSales(String name) =>
      widget.sales.where((sale) => sale.customerName == name).toList();

  bool _isOverdue(List<SaleRecord> customerSales) {
    final today = DateTime.now();
    final startOfToday = DateTime(today.year, today.month, today.day);
    return customerSales.any(
      (sale) =>
          sale.balance > 0 &&
          sale.dueDate != null &&
          sale.dueDate!.isBefore(startOfToday),
    );
  }

  @override
  Widget build(BuildContext context) {
    final names = widget.sales
        .where((sale) => sale.customerName != 'Client comptant')
        .map((sale) => sale.customerName)
        .toSet()
        .toList();
    names.sort();
    final query = search.text.trim().toLowerCase();
    final visibleNames = names.where((name) {
      final customerSales = _customerSales(name);
      final balance = _balanceFor(customerSales);
      final phone = customerSales
          .map((sale) => sale.customerPhone)
          .firstWhere((value) => value.isNotEmpty, orElse: () => '');
      final matchesSearch =
          query.isEmpty ||
          name.toLowerCase().contains(query) ||
          phone.toLowerCase().contains(query);
      final matchesFilter = switch (filter) {
        'À recouvrer' => balance > 0,
        'En retard' => balance > 0 && _isOverdue(customerSales),
        'Soldés' => balance <= 0,
        _ => true,
      };
      return matchesSearch && matchesFilter;
    }).toList();
    final totalDue = widget.sales.fold(0.0, (sum, sale) => sum + sale.balance);
    final overdueNames = names.where((name) {
      final customerSales = _customerSales(name);
      return _balanceFor(customerSales) > 0 && _isOverdue(customerSales);
    }).toList();
    final overdueTotal = overdueNames.fold(
      0.0,
      (sum, name) => sum + _balanceFor(_customerSales(name)),
    );

    return ListView(
      padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 600 ? 16 : 26),
      children: [
        _BizPageHero(
          title: _tr('Clients et crédits', 'Customers and credit'),
          subtitle: _tr(
            'Consulte les soldes dus et enregistre les paiements des clients.',
            'Review outstanding balances and record customer payments.',
          ),
          icon: Icons.people_alt_rounded,
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: 240,
              child: SummaryCard(
                title: _tr('Clients suivis', 'Customers tracked'),
                value: names.length.toString(),
                icon: Icons.people_outline,
                color: navy,
              ),
            ),
            SizedBox(
              width: 240,
              child: SummaryCard(
                title: _tr('Total restant dû', 'Total outstanding'),
                value: _money(totalDue),
                icon: Icons.account_balance_wallet_outlined,
                color: teal,
              ),
            ),
            SizedBox(
              width: 240,
              child: SummaryCard(
                title:
                    _tr('Crédits en retard', 'Overdue credit') +
                    ' • ${overdueNames.length} ${_tr('client(s)', 'customer(s)')}',
                value: _money(overdueTotal),
                icon: Icons.warning_amber_rounded,
                color: overdueNames.isEmpty ? teal : const Color(0xFFB84A52),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        TextField(
          controller: search,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            prefixIcon: Icon(Icons.search),
            labelText: _tr(
              'Rechercher un client ou son téléphone',
              'Search by customer or phone',
            ),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          children: ['Tous', 'À recouvrer', 'En retard', 'Soldés']
              .map(
                (value) => ChoiceChip(
                  label: Text(_customerFilterLabel(value)),
                  selected: filter == value,
                  onSelected: (_) => setState(() => filter = value),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 12),
        if (names.isEmpty)
          Card(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                widget.sales.isEmpty
                    ? _tr(
                        'Les clients apparaîtront ici après une vente.',
                        'Customers will appear here after a sale.',
                      )
                    : _tr(
                        'Aucune vente à crédit nominative pour le moment.',
                        'No named credit sales yet.',
                      ),
              ),
            ),
          )
        else if (visibleNames.isEmpty)
          Card(
            color: Colors.white,
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                _tr(
                  'Aucun client ne correspond à cette recherche ou à ce filtre.',
                  'No customers match this search or filter.',
                ),
              ),
            ),
          )
        else
          ...visibleNames.map((name) {
            final customerSales = _customerSales(name);
            final balance = _balanceFor(customerSales);
            final phone = customerSales
                .map((sale) => sale.customerPhone)
                .firstWhere((value) => value.isNotEmpty, orElse: () => '');
            final oldestDue =
                customerSales
                    .where((sale) => sale.balance > 0 && sale.dueDate != null)
                    .map((sale) => sale.dueDate!)
                    .toList()
                  ..sort();
            final overdue = balance > 0 && _isOverdue(customerSales);
            return Card(
              color: Colors.white,
              elevation: 5,
              shadowColor: const Color(0x1E1B2C73),
              margin: const EdgeInsets.symmetric(vertical: 6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(21),
                side: BorderSide(
                  color: overdue
                      ? const Color(0xFFF0D6D4)
                      : const Color(0xFFE1EAF0),
                ),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 17,
                  vertical: 9,
                ),
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (dialogContext) => CustomerDetailsDialog(
                    customerName: name,
                    customerPhone: phone,
                    sales: customerSales,
                    payments: widget.payments
                        .where((payment) => payment.customerName == name)
                        .toList(),
                    refunds: widget.refunds
                        .where((item) => item.customerName == name)
                        .toList(),
                    onCollectPayment: balance > 0
                        ? () {
                            Navigator.pop(dialogContext);
                            widget.onCollectPayment(name, balance);
                          }
                        : null,
                  ),
                ),
                leading: CircleAvatar(
                  backgroundColor: Colors.transparent,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: overdue
                            ? const [Color(0xFFFFE3DF), Color(0xFFFFF1ED)]
                            : const [Color(0xFFD8F5F0), Color(0xFFE8F0FF)],
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      overdue
                          ? Icons.warning_amber_rounded
                          : Icons.person_outline,
                      color: overdue ? const Color(0xFFB84A52) : teal,
                    ),
                  ),
                ),
                title: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    if (overdue)
                      Chip(
                        label: Text(_tr('En retard', 'Overdue')),
                        visualDensity: VisualDensity.compact,
                      ),
                    const Icon(
                      Icons.chevron_right,
                      size: 20,
                      color: Colors.black45,
                    ),
                  ],
                ),
                subtitle: Text(
                  (phone.isEmpty ? '' : phone + ' • ') +
                      customerSales.length.toString() +
                      ' ${_tr('vente(s)', 'sale(s)')}' +
                      '\n${_tr('Solde dû : ', 'Balance due: ')}' +
                      _money(balance) +
                      (oldestDue.isEmpty
                          ? ''
                          : (overdue
                                    ? ' • ${_tr('Échéance dépassée : ', 'Overdue since: ')}'
                                    : ' • ${_tr('Échéance : ', 'Due: ')}') +
                                _date(oldestDue.first)),
                ),
                isThreeLine: true,
                trailing: balance > 0
                    ? Wrap(
                        spacing: 2,
                        children: [
                          if (phone.isNotEmpty)
                            IconButton(
                              tooltip: _tr(
                                'Préparer un rappel WhatsApp',
                                'Prepare WhatsApp reminder',
                              ),
                              onPressed: () =>
                                  _prepareDebtReminder(name, phone, balance),
                              icon: const Icon(
                                Icons.chat_outlined,
                                color: Color(0xFF168C54),
                              ),
                            ),
                          IconButton(
                            tooltip: _tr(
                              'Enregistrer un paiement',
                              'Record a payment',
                            ),
                            onPressed: () =>
                                widget.onCollectPayment(name, balance),
                            icon: const Icon(
                              Icons.payments_outlined,
                              color: teal,
                            ),
                          ),
                        ],
                      )
                    : const Icon(Icons.check_circle_outline, color: teal),
              ),
            );
          }),
        if (widget.payments.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            _tr('Derniers paiements reçus', 'Recent payments received'),
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.bold,
              color: ink,
            ),
          ),
          const SizedBox(height: 8),
          ...widget.payments
              .take(8)
              .map(
                (payment) => Card(
                  color: Colors.white,
                  child: ListTile(
                    leading: const Icon(Icons.receipt_outlined, color: teal),
                    title: Text(
                      payment.customerName + ' • ' + payment.receiptNumber,
                    ),
                    subtitle: Text(
                      _date(payment.date) +
                          ' • ' +
                          _paymentMethodLabel(payment.paymentMethod) +
                          (payment.note.isEmpty ? '' : ' • ' + payment.note),
                    ),
                    trailing: Text(
                      _money(payment.amount),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
        ],
        const SizedBox(height: 10),
        Text(
          _tr(
            'Les crédits sont séparés des commandes ou colis en attente de retrait.',
            'Credit balances are separate from orders or packages awaiting pickup.',
          ),
          style: TextStyle(fontSize: 12, color: Colors.black45),
        ),
      ],
    );
  }
}

class CustomerDetailsDialog extends StatelessWidget {
  const CustomerDetailsDialog({
    super.key,
    required this.customerName,
    required this.customerPhone,
    required this.sales,
    required this.payments,
    required this.refunds,
    required this.onCollectPayment,
  });

  final String customerName;
  final String customerPhone;
  final List<SaleRecord> sales;
  final List<PaymentRecord> payments;
  final List<RefundRecord> refunds;
  final VoidCallback? onCollectPayment;

  @override
  Widget build(BuildContext context) {
    final total = sales.fold(0.0, (sum, sale) => sum + sale.total);
    final received = sales.fold(0.0, (sum, sale) => sum + sale.received);
    final balance = sales.fold(0.0, (sum, sale) => sum + sale.balance);
    final returned = refunds.fold(0.0, (sum, item) => sum + item.value);
    return AlertDialog(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(customerName),
          if (customerPhone.isNotEmpty)
            Text(
              customerPhone,
              style: const TextStyle(fontSize: 14, color: Colors.black54),
            ),
        ],
      ),
      content: SizedBox(
        width: _dialogWidth(context, 600),
        height: _dialogHeight(
          context,
          MediaQuery.sizeOf(context).height * 0.58,
        ),
        child: ListView(
          children: [
            Card(
              color: const Color(0xFFEAF5F4),
              child: ListTile(
                leading: const Icon(Icons.shopping_bag_outlined, color: teal),
                title: const Text('Ventes nettes après retours'),
                trailing: Text(
                  _money(total),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
            Card(
              color: Colors.white,
              child: ListTile(
                leading: const Icon(Icons.payments_outlined, color: teal),
                title: const Text('Encaissé net'),
                trailing: Text(
                  _money(received),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
            Card(
              color: balance > 0 ? const Color(0xFFFFF3EF) : Colors.white,
              child: ListTile(
                leading: Icon(
                  Icons.account_balance_wallet_outlined,
                  color: balance > 0 ? const Color(0xFFB84A52) : teal,
                ),
                title: const Text('Solde restant dû'),
                trailing: Text(
                  _money(balance),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: balance > 0 ? const Color(0xFFB84A52) : teal,
                  ),
                ),
              ),
            ),
            if (refunds.isNotEmpty)
              Card(
                color: Colors.white,
                child: ListTile(
                  leading: const Icon(
                    Icons.assignment_return_outlined,
                    color: Color(0xFFB84A52),
                  ),
                  title: const Text('Valeur des retours'),
                  trailing: Text(
                    _money(returned),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            const Text(
              'Historique des ventes',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: ink,
              ),
            ),
            const SizedBox(height: 6),
            ...sales.map(
              (sale) => Card(
                color: Colors.white,
                child: ListTile(
                  leading: const Icon(Icons.receipt_long_outlined, color: teal),
                  title: Text(sale.product.name + ' • ' + sale.receiptNumber),
                  subtitle: Text(
                    _dateTime(sale.date) +
                        ' • ' +
                        _quantity(sale.quantity) +
                        ' ' +
                        sale.saleUnit +
                        '\nTotal ' +
                        _money(sale.total) +
                        ' • Encaissé ' +
                        _money(sale.received) +
                        ' • Dû ' +
                        _money(sale.balance),
                  ),
                  isThreeLine: true,
                ),
              ),
            ),
            if (payments.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'Paiements reçus',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: ink,
                ),
              ),
              const SizedBox(height: 6),
              ...payments.map(
                (payment) => Card(
                  color: Colors.white,
                  child: ListTile(
                    leading: const Icon(Icons.payments_outlined, color: teal),
                    title: Text(
                      payment.receiptNumber + ' • ' + _money(payment.amount),
                    ),
                    subtitle: Text(
                      _date(payment.date) +
                          ' • ' +
                          payment.paymentMethod +
                          (payment.note.isEmpty ? '' : ' • ' + payment.note),
                    ),
                  ),
                ),
              ),
            ],
            if (refunds.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'Retours et remboursements',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: ink,
                ),
              ),
              const SizedBox(height: 6),
              ...refunds.map(
                (item) => Card(
                  color: Colors.white,
                  child: ListTile(
                    leading: const Icon(
                      Icons.assignment_return_outlined,
                      color: Color(0xFFB84A52),
                    ),
                    title: Text(item.productName + ' • ' + item.receiptNumber),
                    subtitle: Text(
                      _date(item.date) +
                          ' • ' +
                          _quantity(item.quantity) +
                          ' ' +
                          item.saleUnit +
                          '\nValeur : ' +
                          _money(item.value) +
                          ' • Remboursement versé : ' +
                          _money(item.cashRefund),
                    ),
                    isThreeLine: true,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Fermer'),
        ),
        if (onCollectPayment != null)
          FilledButton.icon(
            onPressed: onCollectPayment,
            icon: const Icon(Icons.payments_outlined),
            label: const Text('Enregistrer un paiement'),
          ),
      ],
    );
  }
}

class AddPaymentDialog extends StatefulWidget {
  const AddPaymentDialog({
    super.key,
    required this.customerName,
    required this.balance,
    required this.receiptNumber,
  });

  final String customerName;
  final double balance;
  final String receiptNumber;

  @override
  State<AddPaymentDialog> createState() => _AddPaymentDialogState();
}

class _AddPaymentDialogState extends State<AddPaymentDialog> {
  final formKey = GlobalKey<FormState>();
  late final amount = TextEditingController(
    text: widget.balance.toStringAsFixed(0),
  );
  final note = TextEditingController();
  String paymentMethod = 'Espèces';

  @override
  void dispose() {
    amount.dispose();
    note.dispose();
    super.dispose();
  }

  void _save() {
    final parsed = double.tryParse(amount.text.trim().replaceAll(',', '.'));
    if (!formKey.currentState!.validate() || parsed == null) return;
    Navigator.pop(
      context,
      PaymentRecord(
        customerName: widget.customerName,
        amount: parsed,
        paymentMethod: paymentMethod,
        receiptNumber: widget.receiptNumber,
        date: DateTime.now(),
        note: note.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Enregistrer un paiement client'),
    content: SizedBox(
      width: _dialogWidth(context, 460),
      child: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Client : ' + widget.customerName),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Solde dû : ' + _money(widget.balance),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              validator: (value) {
                final parsed = double.tryParse(
                  (value ?? '').trim().replaceAll(',', '.'),
                );
                if (parsed == null || parsed <= 0)
                  return 'Saisis un montant supérieur à zéro.';
                if (parsed > widget.balance)
                  return 'Le paiement dépasse le solde dû.';
                return null;
              },
              decoration: InputDecoration(
                labelText: 'Montant reçu ($_currencyLabel)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: paymentMethod,
              decoration: const InputDecoration(
                labelText: 'Mode de paiement',
                border: OutlineInputBorder(),
              ),
              items: const ['Espèces', 'Mobile Money', 'Banque']
                  .map(
                    (value) =>
                        DropdownMenuItem(value: value, child: Text(value)),
                  )
                  .toList(),
              onChanged: (value) =>
                  setState(() => paymentMethod = value ?? paymentMethod),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: note,
              decoration: const InputDecoration(
                labelText: 'Note ou référence (facultatif)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Le montant sera affecté aux ventes impayées les plus anciennes du client.',
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Annuler'),
      ),
      FilledButton(
        onPressed: _save,
        child: Text('Enregistrer • ' + widget.receiptNumber),
      ),
    ],
  );
}

class SalesContent extends StatefulWidget {
  const SalesContent({
    super.key,
    required this.businessId,
    required this.payments,
    required this.sales,
    required this.loadSalesPage,
    required this.refreshKey,
    required this.products,
    required this.onAddProduct,
    required this.onNewSale,
    required this.onEditSale,
    required this.onCancelReceipt,
    required this.onRefundSale,
    required this.onMarkCollected,
    required this.refunds,
    required this.businessProfile,
    required this.businessName,
    this.isStaff = false,
  });

  final String? businessId;
  final List<PaymentRecord> payments;
  final List<SaleRecord> sales;
  final Future<Map<String, dynamic>> Function(int offset, int pageSize)
  loadSalesPage;
  final int refreshKey;
  final List<Product> products;
  final VoidCallback onAddProduct;
  final VoidCallback onNewSale;
  final Future<void> Function(SaleRecord sale) onEditSale;
  final Future<void> Function(SaleRecord sale) onCancelReceipt;
  final Future<void> Function(SaleRecord sale) onRefundSale;
  final Future<void> Function(SaleRecord sale) onMarkCollected;
  final List<RefundRecord> refunds;
  final BusinessProfile businessProfile;
  final String businessName;
  final bool isStaff;

  @override
  State<SalesContent> createState() => _SalesContentState();
}

class _SalesContentState extends State<SalesContent> {
  static const _pageSize = 30;
  final List<SaleRecord> _pageSales = [];
  int _nextOffset = 0;
  int _receiptCount = 0;
  double _totalReceived = 0;
  double _totalDue = 0;
  bool _hasMore = false;
  bool _loading = true;
  bool _pageLoadFailed = false;
  int _requestGeneration = 0;

  @override
  void initState() {
    super.initState();
    _loadPage(reset: true);
  }

  @override
  void didUpdateWidget(covariant SalesContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshKey != widget.refreshKey) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadPage(reset: true);
      });
    }
  }

  Future<void> _loadPage({bool reset = false}) async {
    if (_loading && !reset) return;
    if (reset) _requestGeneration++;
    final generation = _requestGeneration;
    final offset = reset ? 0 : _nextOffset;
    setState(() {
      _loading = true;
      if (reset) {
        _pageSales.clear();
        _nextOffset = 0;
        _pageLoadFailed = false;
      }
    });
    try {
      final result = await widget
          .loadSalesPage(offset, _pageSize)
          .timeout(const Duration(seconds: 12));
      final rows = (result['sales'] as List? ?? [])
          .map((row) => SaleRecord.fromJson(Map<String, dynamic>.from(row)))
          .toList();
      if (!mounted) return;
      if (generation != _requestGeneration) return;
      setState(() {
        if (reset) _pageSales.clear();
        _pageSales.addAll(rows);
        _receiptCount = (result['totalReceipts'] as num?)?.toInt() ?? 0;
        _totalReceived = (result['totalReceived'] as num?)?.toDouble() ?? 0;
        _totalDue = (result['totalDue'] as num?)?.toDouble() ?? 0;
        _hasMore = result['hasMore'] as bool? ?? false;
        _nextOffset = offset + _pageSize;
        _pageLoadFailed = false;
        _loading = false;
      });
    } catch (error) {
      debugPrint('Chargement paginé des ventes impossible : $error');
      if (!mounted) return;
      if (generation != _requestGeneration) return;
      setState(() {
        _pageLoadFailed = true;
        _hasMore = false;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Keep the locally saved sale visible while the cloud page request is
    // pending. Mobile networks can leave that request waiting much longer
    // than desktop browsers do when the device is offline.
    final showLocalSalesWhileLoading =
        _loading && _pageSales.isEmpty && widget.sales.isNotEmpty;
    final useLocalSales = _pageLoadFailed || showLocalSalesWhileLoading;
    final sales = useLocalSales ? widget.sales : _pageSales;
    final totalReceived = useLocalSales
        ? widget.sales.fold(0.0, (sum, sale) => sum + sale.received)
        : _totalReceived;
    final totalDue = useLocalSales
        ? widget.sales.fold(0.0, (sum, sale) => sum + sale.balance)
        : _totalDue;
    final receiptCount = useLocalSales
        ? widget.sales.map((sale) => sale.receiptNumber).toSet().length
        : _receiptCount;
    final products = widget.products;
    final refunds = widget.refunds;
    final isStaff = widget.isStaff;
    final onNewSale = widget.onNewSale;
    final onAddProduct = widget.onAddProduct;
    final onEditSale = widget.onEditSale;
    final onCancelReceipt = widget.onCancelReceipt;
    final onRefundSale = widget.onRefundSale;
    final onMarkCollected = widget.onMarkCollected;
    final businessName = widget.businessName;
    final businessProfile = widget.businessProfile;
    return ListView(
      padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 600 ? 16 : 26),
      children: [
        _BizPageHero(
          title: _tr('Ventes', 'Sales'),
          subtitle: _tr(
            'Enregistre les ventes, les paiements et les retraits.',
            'Record sales, payments, and customer pickups.',
          ),
          icon: Icons.point_of_sale_rounded,
          action: FilledButton.icon(
            onPressed: isStaff && products.isEmpty ? null : onNewSale,
            icon: const Icon(Icons.add),
            label: Text(_tr('Nouvelle vente', 'New sale')),
          ),
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: 230,
              child: SummaryCard(
                title: _tr('Reçus enregistrés', 'Receipts recorded'),
                value: receiptCount.toString(),
                icon: Icons.receipt_long_outlined,
                color: navy,
              ),
            ),
            SizedBox(
              width: 230,
              child: SummaryCard(
                title: _tr('Montant encaissé', 'Amount received'),
                value: _money(totalReceived),
                icon: Icons.payments_outlined,
                color: teal,
              ),
            ),
            SizedBox(
              width: 230,
              child: SummaryCard(
                title: _tr('Reste à recouvrer', 'Outstanding balance'),
                value: _money(totalDue),
                icon: Icons.account_balance_wallet_outlined,
                color: totalDue > 0 ? const Color(0xFFB84A52) : teal,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        if (isStaff) ...[
          LocalAssistantCard(
            businessId: widget.businessId,
            periodSales: sales,
            allSales: widget.sales,
            products: products,
            purchases: const [],
            payments: widget.payments,
            expenses: const [],
            refunds: refunds,
            cashMovements: const [],
            canUseOnlineAI: false,
            canSeeFullData: false,
            periodRevenue: sales.fold(0, (sum, sale) => sum + sale.total),
            netProfit: sales.fold(0, (sum, sale) => sum + sale.grossProfit),
            selectedPeriod: 'Tout',
          ),
          const SizedBox(height: 16),
        ],
        if (products.isEmpty)
          Card(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                children: [
                  Text(
                    isStaff
                        ? _tr(
                            'Aucun produit disponible. Demande au propriétaire ou à un administrateur d’ajouter les produits.',
                            'No products available. Ask the owner or an administrator to add products.',
                          )
                        : _tr(
                            'Ajoute d’abord des produits au stock pour pouvoir les vendre.',
                            'Add products to inventory before making a sale.',
                          ),
                  ),
                  if (!isStaff) ...[
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: onAddProduct,
                      icon: const Icon(Icons.add),
                      label: Text(_tr('Ajouter un produit', 'Add a product')),
                    ),
                  ],
                ],
              ),
            ),
          )
        else if (sales.isEmpty)
          Card(
            color: Colors.white,
            child: Padding(
              padding: EdgeInsets.all(28),
              child: Center(
                child: Text(
                  _tr(
                    'Aucune vente enregistrée pour le moment.',
                    'No sales recorded yet.',
                  ),
                ),
              ),
            ),
          )
        else
          ...sales.map((sale) {
            final receiptSales = sales
                .where((item) => item.receiptNumber == sale.receiptNumber)
                .toList();
            final hasRefund = refunds.any(
              (item) => item.receiptNumber == sale.receiptNumber,
            );
            final canEditReceipt =
                receiptSales.every((item) => item.received <= 0) && !hasRefund;
            final canCancelReceipt =
                receiptSales.every((item) => item.received <= 0) && !hasRefund;
            final isOverdue =
                sale.balance > 0 &&
                sale.dueDate != null &&
                sale.dueDate!.isBefore(
                  DateTime(
                    DateTime.now().year,
                    DateTime.now().month,
                    DateTime.now().day,
                  ),
                );
            return Card(
              color: Colors.white,
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: isOverdue
                      ? const Color(0xFFFFE3DF)
                      : const Color(0xFFE8EAFE),
                  child: Icon(
                    isOverdue
                        ? Icons.warning_amber_rounded
                        : Icons.receipt_long_outlined,
                    color: isOverdue ? const Color(0xFFB84A52) : navy,
                  ),
                ),
                title: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    Text(
                      sale.product.name + ' • ' + sale.receiptNumber,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Chip(
                      label: Text(
                        isOverdue
                            ? _tr('En retard', 'Overdue')
                            : sale.balance > 0
                            ? _tr('À crédit', 'On credit')
                            : _tr('Payé', 'Paid'),
                      ),
                      visualDensity: VisualDensity.compact,
                      backgroundColor: isOverdue
                          ? const Color(0xFFFFE3DF)
                          : sale.balance > 0
                          ? const Color(0xFFFFF1E4)
                          : const Color(0xFFE4F4EC),
                      labelStyle: TextStyle(
                        color: isOverdue
                            ? const Color(0xFFB84A52)
                            : sale.balance > 0
                            ? const Color(0xFF9A5A12)
                            : const Color(0xFF287A54),
                        fontSize: 12,
                      ),
                    ),
                    if (sale.pickupStatus == 'À retirer')
                      Chip(
                        label: Text(_tr('À retirer', 'Ready for pickup')),
                        visualDensity: VisualDensity.compact,
                        backgroundColor: Color(0xFFE8EAFE),
                        labelStyle: TextStyle(color: navy, fontSize: 12),
                      ),
                  ],
                ),
                subtitle: Text(
                  _dateTime(sale.date) +
                      ' • ' +
                      _customerLabel(sale.customerName) +
                      '\n' +
                      _quantity(sale.quantity) +
                      ' ' +
                      _unitLabel(sale.saleUnit) +
                      ' × ' +
                      _money(sale.unitPrice) +
                      '\n' +
                      _tr('Total ', 'Total ') +
                      _money(sale.total) +
                      ' • ' +
                      _tr('Encaissé ', 'Received ') +
                      _money(sale.received) +
                      (sale.balance > 0
                          ? ' • ${_tr('Reste dû ', 'Balance due ')}' +
                                _money(sale.balance)
                          : ' • ' + _tr('Payé', 'Paid')) +
                      '\n' +
                      _tr('Mode initial : ', 'Initial payment: ') +
                      _paymentMethodLabel(sale.paymentMethod) +
                      '\n' +
                      _tr('Colis : ', 'Package: ') +
                      _pickupStatusLabel(sale.pickupStatus) +
                      (sale.collectedAt == null
                          ? ''
                          : ' • ' + _date(sale.collectedAt!)) +
                      (sale.dueDate == null
                          ? ''
                          : ' • ' +
                                _tr('Rappel : ', 'Due: ') +
                                _date(sale.dueDate!)),
                ),
                isThreeLine: true,
                trailing: PopupMenuButton<String>(
                  tooltip: _tr('Actions sur la vente', 'Sale actions'),
                  onSelected: (action) {
                    if (action == 'print')
                      showDialog<void>(
                        context: context,
                        builder: (_) => ReceiptDialog(
                          sales: receiptSales,
                          businessName: businessName,
                          profile: businessProfile,
                        ),
                      );
                    if (action == 'edit') onEditSale(sale);
                    if (action == 'cancel') onCancelReceipt(sale);
                    if (action == 'refund') onRefundSale(sale);
                    if (action == 'collect') onMarkCollected(sale);
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'print',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.print_outlined),
                        title: Text(
                          _tr(
                            'Afficher / imprimer le reçu',
                            'View / print receipt',
                          ),
                        ),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'collect',
                      enabled: sale.pickupStatus == 'À retirer',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.inventory_2_outlined),
                        title: Text(
                          sale.pickupStatus == 'À retirer'
                              ? _tr(
                                  'Confirmer le retrait du colis',
                                  'Confirm package pickup',
                                )
                              : '${_tr('Colis : ', 'Package: ')}${_pickupStatusLabel(sale.pickupStatus)}',
                        ),
                      ),
                    ),
                    if (!isStaff) ...[
                      PopupMenuItem(
                        value: 'refund',
                        enabled: sale.quantity > 0,
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.assignment_return_outlined),
                          title: Text(
                            sale.quantity > 0
                                ? _tr(
                                    'Retour / remboursement',
                                    'Return / refund',
                                  )
                                : _tr(
                                    'Article déjà retourné',
                                    'Item already returned',
                                  ),
                          ),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'edit',
                        enabled: canEditReceipt && sale.quantity > 0,
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.edit_outlined),
                          title: Text(
                            !canEditReceipt && hasRefund
                                ? _tr(
                                    'Modification bloquée : retour enregistré',
                                    'Editing blocked: a return was recorded',
                                  )
                                : !canEditReceipt
                                ? _tr(
                                    'Modification bloquée : paiement reçu',
                                    'Editing blocked: payment received',
                                  )
                                : sale.quantity <= 0
                                ? _tr(
                                    'Article déjà retourné',
                                    'Item already returned',
                                  )
                                : _tr('Modifier cette ligne', 'Edit this line'),
                          ),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'cancel',
                        enabled: canCancelReceipt,
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.delete_outline),
                          title: Text(
                            canCancelReceipt
                                ? _tr(
                                    'Annuler tout le reçu',
                                    'Cancel entire receipt',
                                  )
                                : hasRefund
                                ? _tr(
                                    'Annulation bloquée : retour enregistré',
                                    'Cancellation blocked: a return was recorded',
                                  )
                                : _tr(
                                    'Annulation bloquée : paiement reçu',
                                    'Cancellation blocked: payment received',
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ],
                  icon: const Icon(Icons.more_vert),
                ),
              ),
            );
          }),
        if (!_pageLoadFailed &&
            (_hasMore || (_loading && !showLocalSalesWhileLoading))) ...[
          const SizedBox(height: 8),
          Center(
            child: _loading
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(),
                  )
                : OutlinedButton.icon(
                    onPressed: () => _loadPage(),
                    icon: const Icon(Icons.expand_more),
                    label: Text(
                      _tr(
                        'Charger les reçus suivants (30 par page)',
                        'Load next receipts (30 per page)',
                      ),
                    ),
                  ),
          ),
        ],
        if (_pageLoadFailed)
          Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              _tr(
                'Historique chargé depuis la copie locale : pagination cloud indisponible.',
                'History loaded from the local copy: cloud pagination is unavailable.',
              ),
              style: TextStyle(color: Colors.black54, fontSize: 12),
            ),
          ),
        if (refunds.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            _tr(
              'Retours et remboursements récents',
              'Recent returns and refunds',
            ),
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.bold,
              color: ink,
            ),
          ),
          const SizedBox(height: 8),
          ...refunds
              .take(10)
              .map(
                (item) => Card(
                  color: Colors.white,
                  child: ListTile(
                    leading: const Icon(
                      Icons.assignment_return_outlined,
                      color: Color(0xFFB84A52),
                    ),
                    title: Text('${item.productName} • ${item.receiptNumber}'),
                    subtitle: Text(
                      '${_customerLabel(item.customerName)} • ${_quantity(item.quantity)} ${_unitLabel(item.saleUnit)} • ${_date(item.date)}\n${_tr('Valeur rendue : ', 'Returned value: ')}${_money(item.value)} • ${_tr('Remboursé en espèces : ', 'Cash refunded: ')}${_money(item.cashRefund)}${item.cashRefund > 0 ? ' • ${_paymentMethodLabel(item.paymentMethod)}' : ''}',
                    ),
                    isThreeLine: true,
                  ),
                ),
              ),
        ],
        const SizedBox(height: 10),
        Text(
          _tr(
            'Les reçus sont chargés par pages de 30. Les totaux viennent de tout l’historique cloud; les données restent aussi disponibles hors connexion.',
            'Receipts load 30 at a time. Totals use the full cloud history; data also remains available offline.',
          ),
          style: TextStyle(fontSize: 12, color: Colors.black45),
        ),
      ],
    );
  }
}

class EditSaleDialog extends StatefulWidget {
  const EditSaleDialog({super.key, required this.sale, required this.products});
  final SaleRecord sale;
  final List<Product> products;

  @override
  State<EditSaleDialog> createState() => _EditSaleDialogState();
}

class _EditSaleDialogState extends State<EditSaleDialog> {
  final formKey = GlobalKey<FormState>();
  late Product selectedProduct;
  late String saleType;
  late final quantity = TextEditingController(
    text: widget.sale.quantity
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'\.00$'), ''),
  );
  late final price = TextEditingController(
    text: widget.sale.unitPrice.toStringAsFixed(0),
  );

  bool _sameProduct(Product a, Product b) =>
      a.name == b.name && a.category == b.category;

  List<Product> get productChoices =>
      widget.products.any((item) => _sameProduct(item, selectedProduct))
      ? widget.products
      : [selectedProduct, ...widget.products];

  String get saleUnit =>
      saleType == 'Gros' ? selectedProduct.unit : selectedProduct.retailUnit;

  double get _number =>
      double.tryParse(quantity.text.trim().replaceAll(',', '.')) ?? 0;
  double get _unitPrice =>
      double.tryParse(price.text.trim().replaceAll(',', '.')) ?? 0;
  double get _stockQuantity =>
      saleType == 'Gros' || selectedProduct.retailUnit == selectedProduct.unit
      ? _number
      : _number / selectedProduct.retailUnitsPerStockUnit;

  @override
  void initState() {
    super.initState();
    selectedProduct = widget.products.firstWhere(
      (item) => _sameProduct(item, widget.sale.product),
      orElse: () => widget.sale.product,
    );
    saleType = widget.sale.saleUnit == selectedProduct.unit ? 'Gros' : 'Détail';
  }

  @override
  void dispose() {
    quantity.dispose();
    price.dispose();
    super.dispose();
  }

  String? _positive(String? value) {
    final parsed = double.tryParse((value ?? '').trim().replaceAll(',', '.'));
    return parsed == null || parsed <= 0
        ? 'Saisis un nombre supérieur à zéro.'
        : null;
  }

  void _save() {
    if (!formKey.currentState!.validate()) return;
    final sameAsSoldProduct = _sameProduct(
      selectedProduct,
      widget.sale.product,
    );
    final available =
        selectedProduct.quantity +
        (sameAsSoldProduct ? widget.sale.stockQuantity : 0);
    if (_stockQuantity > available) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Stock insuffisant. Disponible : ${_quantity(available)} ${selectedProduct.unit}.',
          ),
        ),
      );
      return;
    }
    final total = _number * _unitPrice;
    Navigator.pop(
      context,
      SaleRecord(
        receiptNumber: widget.sale.receiptNumber,
        product: selectedProduct,
        customerName: widget.sale.customerName,
        customerPhone: widget.sale.customerPhone,
        quantity: _number,
        saleUnit: saleUnit,
        stockQuantity: _stockQuantity,
        unitPrice: _unitPrice,
        total: total,
        received: 0,
        balance: total,
        paymentMethod: widget.sale.paymentMethod,
        date: widget.sale.date,
        dueDate: total > 0 ? widget.sale.dueDate : null,
        pickupStatus: widget.sale.pickupStatus,
        collectedAt: widget.sale.collectedAt,
        initialReceived: widget.sale.initialReceived ?? 0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Modifier la vente • ${widget.sale.receiptNumber}'),
    content: SizedBox(
      width: _dialogWidth(context, 480),
      child: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<Product>(
              value: selectedProduct,
              decoration: const InputDecoration(
                labelText: 'Produit',
                border: OutlineInputBorder(),
              ),
              items: productChoices
                  .map(
                    (item) =>
                        DropdownMenuItem(value: item, child: Text(item.name)),
                  )
                  .toList(),
              onChanged: (item) => setState(() {
                if (item == null) return;
                selectedProduct = item;
                price.text =
                    (saleType == 'Gros'
                            ? item.wholesalePrice
                            : item.retailPrice)
                        .toStringAsFixed(0);
              }),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: saleType,
              decoration: const InputDecoration(
                labelText: 'Type de vente',
                border: OutlineInputBorder(),
              ),
              items: const ['Détail', 'Gros']
                  .map(
                    (item) => DropdownMenuItem(value: item, child: Text(item)),
                  )
                  .toList(),
              onChanged: (item) => setState(() {
                saleType = item ?? saleType;
                price.text =
                    (saleType == 'Gros'
                            ? selectedProduct.wholesalePrice
                            : selectedProduct.retailPrice)
                        .toStringAsFixed(0);
              }),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: quantity,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              validator: _positive,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Quantité en $saleUnit',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: price,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              validator: _positive,
              decoration: InputDecoration(
                labelText: 'Prix par $saleUnit ($_currencyLabel)',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Cette ligne n’a pas encore de paiement enregistré; le client et le numéro du reçu seront conservés.',
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Garder la vente'),
      ),
      FilledButton(
        onPressed: _save,
        child: const Text('Enregistrer les changements'),
      ),
    ],
  );
}

class ReceiptDialog extends StatelessWidget {
  const ReceiptDialog({
    super.key,
    required this.sales,
    required this.businessName,
    required this.profile,
  });
  final List<SaleRecord> sales;
  final String businessName;
  final BusinessProfile profile;

  Future<void> _print() async {
    final receipt = sales;
    Uint8List? logoBytes;
    if (profile.logoUrl.isNotEmpty) {
      try {
        final data = await NetworkAssetBundle(Uri.parse(profile.logoUrl))
            .load(profile.logoUrl);
        logoBytes = data.buffer.asUint8List();
      } catch (_) {
        // Certaines banques d’images refusent le chargement direct depuis le navigateur.
      }
    }
    await Printing.layoutPdf(
      name: 'Recu-${receipt.first.receiptNumber}.pdf',
      onLayout: (_) => _buildReceiptPdf(
        receipt,
        businessName: businessName,
        profile: profile,
        logoBytes: logoBytes,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final first = sales.first;
    final total = sales.fold(0.0, (sum, item) => sum + item.total);
    final received = sales.fold(0.0, (sum, item) => sum + item.received);
    final balance = sales.fold(0.0, (sum, item) => sum + item.balance);
    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      title: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: navy,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            const CircleAvatar(
              backgroundColor: Colors.white24,
              child: Icon(Icons.receipt_long_rounded, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Reçu de vente',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    first.receiptNumber,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: balance > 0
                    ? const Color(0xFFFFE8D0)
                    : const Color(0xFFDDF4E9),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                balance > 0 ? 'Partiellement payé' : 'Payé',
                style: TextStyle(
                  color: balance > 0
                      ? const Color(0xFF9A5A13)
                      : const Color(0xFF24734D),
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
      content: SizedBox(
        width: _dialogWidth(context, 600),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (profile.logoUrl.isNotEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Image.network(
                      profile.logoUrl,
                      height: 56,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F6FC),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      businessName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                        color: ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (profile.address.isNotEmpty) Text(profile.address),
                    if (profile.phone.isNotEmpty) Text('Tél. ${profile.phone}'),
                    const Divider(height: 20),
                    Wrap(
                      spacing: 14,
                      runSpacing: 4,
                      children: [
                        Text('Date : ${_dateTime(first.date)}'),
                        Text('Client : ${first.customerName}'),
                        if (first.customerPhone.isNotEmpty)
                          Text('Tél. ${first.customerPhone}'),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Détails de la commande',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: ink,
                ),
              ),
              const SizedBox(height: 8),
              ...sales.map(
                (item) => Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 9,
                    horizontal: 10,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          '${item.product.name}\n${_quantity(item.quantity)} ${item.saleUnit} × ${_money(item.unitPrice)}',
                          style: const TextStyle(height: 1.45),
                        ),
                      ),
                      Text(
                        _money(item.total),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 20),
              _receiptAmount('Sous-total', total),
              _receiptAmount('Total', total, emphasized: true),
              _receiptAmount('Payé', received),
              _receiptAmount('Reste dû', balance, emphasized: balance > 0),
              const SizedBox(height: 12),
              Text('Mode de paiement : ' + first.paymentMethod),
              const SizedBox(height: 12),
              Center(child: Text(profile.receiptFooter)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Fermer'),
        ),
        FilledButton.icon(
          onPressed: _print,
          icon: const Icon(Icons.print),
          label: const Text('Imprimer / PDF'),
        ),
      ],
    );
  }
}

Widget _receiptAmount(String title, double amount, {bool emphasized = false}) =>
    Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontWeight: emphasized ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          Text(
            _money(amount),
            style: TextStyle(
              fontWeight: emphasized ? FontWeight.bold : FontWeight.normal,
              color: emphasized ? const Color(0xFFB84A52) : ink,
            ),
          ),
        ],
      ),
    );

Future<Uint8List> _buildReceiptPdf(
  List<SaleRecord> sales, {
  required String businessName,
  required BusinessProfile profile,
  Uint8List? logoBytes,
}) async {
  final pdf = pw.Document();
  final first = sales.first;
  final total = sales.fold(0.0, (sum, item) => sum + item.total);
  final received = sales.fold(0.0, (sum, item) => sum + item.received);
  final balance = sales.fold(0.0, (sum, item) => sum + item.balance);
  pdf.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a5,
      margin: const pw.EdgeInsets.all(28),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          if (logoBytes != null)
            pw.Center(child: pw.Image(pw.MemoryImage(logoBytes), height: 48)),
          pw.Center(
            child: pw.Text(
              businessName,
              style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
            ),
          ),
          if (profile.phone.isNotEmpty)
            pw.Center(child: pw.Text('Téléphone : ${profile.phone}')),
          if (profile.address.isNotEmpty)
            pw.Center(child: pw.Text(profile.address)),
          pw.SizedBox(height: 8),
          pw.Center(child: pw.Text('REÇU DE VENTE • ${first.receiptNumber}')),
          pw.SizedBox(height: 6),
          pw.Center(child: pw.Text(_dateTime(first.date))),
          pw.Divider(),
          pw.Text(
            'Client : ${first.customerName}',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
          if (first.customerPhone.isNotEmpty)
            pw.Text('Téléphone : ${first.customerPhone}'),
          pw.SizedBox(height: 14),
          ...sales.map(
            (item) => pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 5),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: pw.Text(
                      '${item.product.name}\n${_quantity(item.quantity)} ${item.saleUnit} × ${_money(item.unitPrice)}',
                    ),
                  ),
                  pw.Text(
                    _money(item.total),
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
          pw.Divider(),
          ...[
            ['Total', total],
            ['Payé', received],
            ['Reste dû', balance],
          ].map(
            (row) => pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 3),
              child: pw.Row(
                children: [
                  pw.Expanded(child: pw.Text(row[0] as String)),
                  pw.Text(
                    _money((row[1] as num).toDouble()),
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Text('Mode de paiement : ${first.paymentMethod}'),
          pw.Spacer(),
          pw.Center(child: pw.Text(profile.receiptFooter)),
        ],
      ),
    ),
  );
  return pdf.save();
}

class AddSaleDialog extends StatefulWidget {
  const AddSaleDialog({
    super.key,
    required this.products,
    required this.receiptNumber,
  });
  final List<Product> products;
  final String receiptNumber;

  @override
  State<AddSaleDialog> createState() => _AddSaleDialogState();
}

class _SaleDraft {
  _SaleDraft(this.product)
    : productSearch = TextEditingController(text: product.name),
      price = TextEditingController(
        text: product.retailPrice.toStringAsFixed(0),
      );
  Product product;
  final TextEditingController productSearch;
  final quantity = TextEditingController(text: '1');
  late final TextEditingController price;
  String saleType = 'Détail';
  String get unit => saleType == 'Gros' ? product.unit : product.retailUnit;
  double get stockQuantity {
    final count =
        double.tryParse(quantity.text.trim().replaceAll(',', '.')) ?? 0;
    return saleType == 'Gros' || product.retailUnit == product.unit
        ? count
        : count / product.retailUnitsPerStockUnit;
  }

  void dispose() {
    productSearch.dispose();
    quantity.dispose();
    price.dispose();
  }
}

class _SaleSectionHeading extends StatelessWidget {
  const _SaleSectionHeading({required this.icon, required this.title});
  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 8),
    child: Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: const Color(0xFFE6F5F3),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, color: teal, size: 19),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: ink,
          ),
        ),
      ],
    ),
  );
}

class _AddSaleDialogState extends State<AddSaleDialog> {
  final formKey = GlobalKey<FormState>();
  final barcodeSearch = TextEditingController();
  final customer = TextEditingController();
  final phone = TextEditingController();
  final received = TextEditingController(text: '0');
  late final List<_SaleDraft> lines = [
    _SaleDraft(
      widget.products.firstWhere(
        (product) => product.quantity > 0,
        orElse: () => widget.products.first,
      ),
    ),
  ];
  String paymentMethod = 'Espèces';
  DateTime? dueDate;
  bool pickupLater = false;
  bool _initialLineTouched = false;

  @override
  void dispose() {
    for (final line in lines) {
      line.dispose();
    }
    customer.dispose();
    phone.dispose();
    received.dispose();
    barcodeSearch.dispose();
    super.dispose();
  }

  double _value(TextEditingController c) =>
      double.tryParse(c.text.trim().replaceAll(',', '.')) ?? 0;
  double get total => lines.fold(
    0.0,
    (sum, line) => sum + _value(line.quantity) * _value(line.price),
  );
  double get balance =>
      (total - _value(received)).clamp(0.0, double.infinity).toDouble();

  String? _positiveNumber(String? value) {
    final parsed = double.tryParse((value ?? '').trim().replaceAll(',', '.'));
    if (parsed == null || parsed <= 0)
      return 'Saisis un nombre supérieur à zéro.';
    return null;
  }

  String? _paymentValidator(String? value) {
    final parsed = double.tryParse((value ?? '').trim().replaceAll(',', '.'));
    if (parsed == null || parsed < 0) return 'Saisis un montant valide.';
    if (parsed > total) return 'Le paiement ne peut pas dépasser le total.';
    return null;
  }

  String? _customerValidator(String? value) {
    if (balance > 0 && (value == null || value.trim().isEmpty)) {
      return 'Indique le nom du client pour suivre son crédit.';
    }
    return null;
  }

  void _addByBarcode(String rawCode) {
    final code = rawCode.trim().toLowerCase();
    if (code.isEmpty) return;
    final matches = widget.products
        .where((product) => product.barcode.trim().toLowerCase() == code)
        .toList();
    if (matches.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Aucun produit ne correspond à ce code-barres. Ajoute d’abord le code dans la fiche du produit.',
          ),
        ),
      );
      return;
    }
    if (matches.length > 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Ce code-barres est associé à plusieurs produits. Corrige les fiches avant de continuer.',
          ),
        ),
      );
      return;
    }
    final product = matches.first;
    if (product.quantity <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${product.name} est en rupture de stock.')),
      );
      return;
    }
    setState(() {
      if (!_initialLineTouched && lines.length == 1) {
        final line = lines.first;
        line.product = product;
        line.productSearch.text = product.name;
        line.saleType = 'Détail';
        line.price.text = product.retailPrice.toStringAsFixed(0);
        line.quantity.text = '1';
        _initialLineTouched = true;
      } else {
        final existingIndex = lines.indexWhere(
          (line) => line.product == product && line.saleType == 'Détail',
        );
        if (existingIndex >= 0) {
          final existing = lines[existingIndex];
          existing.quantity.text = (_value(existing.quantity) + 1).toString();
        } else {
          final line = _SaleDraft(product);
          lines.add(line);
        }
        _initialLineTouched = true;
      }
      barcodeSearch.clear();
    });
  }

  Future<void> _scanSaleBarcode() async {
    final code = await showBarcodeScanner(context);
    if (code != null) _addByBarcode(code);
  }

  void _save() {
    if (!formKey.currentState!.validate()) return;
    final requiredStockByProduct = <Product, double>{};
    for (final line in lines) {
      requiredStockByProduct.update(
        line.product,
        (current) => current + line.stockQuantity,
        ifAbsent: () => line.stockQuantity,
      );
    }
    for (final entry in requiredStockByProduct.entries) {
      if (entry.value > entry.key.quantity + 0.000001) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Stock insuffisant pour ${entry.key.name}. Demandé : '
              '${_quantity(entry.value)} ${entry.key.unit}; disponible : '
              '${_quantity(entry.key.quantity)} ${entry.key.unit}.',
            ),
          ),
        );
        return;
      }
    }

    var remainingReceived = _value(received);
    final customerName = customer.text.trim().isEmpty
        ? 'Client comptant'
        : customer.text.trim();
    final now = DateTime.now();
    final batch = <SaleRecord>[];
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      final lineTotal = _value(line.quantity) * _value(line.price);
      final lineReceived = index == lines.length - 1
          ? remainingReceived
          : (_value(received) * lineTotal / total)
                .clamp(0.0, remainingReceived)
                .toDouble();
      remainingReceived -= lineReceived;
      batch.add(
        SaleRecord(
          receiptNumber: widget.receiptNumber,
          product: line.product,
          customerName: customerName,
          customerPhone: phone.text.trim(),
          quantity: _value(line.quantity),
          saleUnit: line.unit,
          stockQuantity: line.stockQuantity,
          unitPrice: _value(line.price),
          total: lineTotal,
          received: lineReceived,
          balance: lineTotal - lineReceived,
          paymentMethod: paymentMethod,
          date: now,
          dueDate: lineTotal - lineReceived > 0 ? dueDate : null,
          pickupStatus: pickupLater ? 'À retirer' : 'Remis au client',
          initialReceived: lineReceived,
        ),
      );
    }
    Navigator.pop(context, batch);
  }

  Future<void> _chooseDueDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (selected != null) setState(() => dueDate = selected);
  }

  Widget _amountField(
    TextEditingController controller,
    String label, {
    String? Function(String?)? validator,
    VoidCallback? onEdited,
  }) => TextFormField(
    controller: controller,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    validator: validator,
    onChanged: (_) => setState(() {
      onEdited?.call();
    }),
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
    ),
  );

  @override
  Widget build(BuildContext context) => AlertDialog(
    titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
    contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
    title: Row(
      children: [
        const CircleAvatar(
          backgroundColor: Color(0xFFE7EAFE),
          child: Icon(Icons.point_of_sale_rounded, color: navy),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Nouvelle vente',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                  color: ink,
                ),
              ),
              Text(
                widget.receiptNumber,
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ],
          ),
        ),
      ],
    ),
    content: SizedBox(
      width: _dialogWidth(context, 760),
      child: SingleChildScrollView(
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: barcodeSearch,
                      keyboardType: TextInputType.number,
                      onFieldSubmitted: _addByBarcode,
                      decoration: const InputDecoration(
                        labelText: 'Code-barres',
                        prefixIcon: Icon(Icons.qr_code_2),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: 'Scanner un produit',
                    onPressed: _scanSaleBarcode,
                    icon: const Icon(Icons.camera_alt_outlined),
                  ),
                  IconButton.filledTonal(
                    tooltip: 'Ajouter le code saisi',
                    onPressed: () => _addByBarcode(barcodeSearch.text),
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const _SaleSectionHeading(
                icon: Icons.shopping_basket_outlined,
                title: 'Articles du panier',
              ),
              ...lines.asMap().entries.map((entry) {
                final index = entry.key;
                final line = entry.value;
                return Card(
                  elevation: 4,
                  shadowColor: const Color(0x221B2C73),
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                    side: const BorderSide(color: Color(0xFFE0E8F0)),
                  ),
                  margin: const EdgeInsets.only(bottom: 10),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: line.productSearch,
                                decoration: const InputDecoration(
                                  labelText: 'Rechercher un produit par nom',
                                  prefixIcon: Icon(Icons.search),
                                  border: OutlineInputBorder(),
                                ),
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                            IconButton(
                              onPressed: lines.length == 1
                                  ? null
                                  : () => setState(() {
                                      lines.removeAt(index).dispose();
                                    }),
                              icon: const Icon(Icons.delete_outline),
                              tooltip: 'Retirer du panier',
                            ),
                          ],
                        ),
                        if (line.productSearch.text.trim().toLowerCase() !=
                            line.product.name.trim().toLowerCase()) ...[
                          const SizedBox(height: 6),
                          Builder(
                            builder: (context) {
                              final query = _normalizeStockSearch(
                                line.productSearch.text,
                              );
                              final matches = widget.products
                                  .where(
                                    (product) =>
                                        product.quantity > 0 &&
                                        !lines.asMap().entries.any(
                                          (other) =>
                                              other.key != index &&
                                              other.value.product == product,
                                        ) &&
                                        (query.isEmpty ||
                                            _matchesStockSearch(
                                              product,
                                              query,
                                            )),
                                  )
                                  .take(8)
                                  .toList();
                              return Container(
                                constraints: const BoxConstraints(
                                  maxHeight: 220,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEAF1FF),
                                  border: Border.all(
                                    color: const Color(0xFF9CB7F2),
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: matches.isEmpty
                                    ? const Padding(
                                        padding: EdgeInsets.all(12),
                                        child: Text('Aucun produit trouvé.'),
                                      )
                                    : ListView.separated(
                                        shrinkWrap: true,
                                        itemCount: matches.length,
                                        separatorBuilder: (_, _) =>
                                            const Divider(height: 1),
                                        itemBuilder: (context, matchIndex) {
                                          final product = matches[matchIndex];
                                          return ListTile(
                                            dense: true,
                                            leading: const Icon(
                                              Icons.inventory_2_outlined,
                                              color: Color(0xFF315FCE),
                                            ),
                                            title: Text(
                                              product.name,
                                              style: const TextStyle(
                                                color: Color(0xFF173A8A),
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            subtitle: Text(
                                              'Stock ${_quantity(product.quantity)} ${product.unit}',
                                            ),
                                            onTap: () => setState(() {
                                              _initialLineTouched = true;
                                              line.product = product;
                                              line.productSearch.text =
                                                  product.name;
                                              line.productSearch.selection =
                                                  TextSelection.collapsed(
                                                    offset: product.name.length,
                                                  );
                                              line.price.text =
                                                  (line.saleType == 'Gros'
                                                          ? product
                                                                .wholesalePrice
                                                          : product.retailPrice)
                                                      .toStringAsFixed(0);
                                            }),
                                          );
                                        },
                                      ),
                              );
                            },
                          ),
                        ],
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                value: line.saleType,
                                decoration: const InputDecoration(
                                  labelText: 'Type de vente',
                                  border: OutlineInputBorder(),
                                ),
                                items: const ['Détail', 'Gros']
                                    .map(
                                      (v) => DropdownMenuItem(
                                        value: v,
                                        child: Text(v),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (v) => setState(() {
                                  _initialLineTouched = true;
                                  line.saleType = v ?? line.saleType;
                                  line.price.text =
                                      (line.saleType == 'Gros'
                                              ? line.product.wholesalePrice
                                              : line.product.retailPrice)
                                          .toStringAsFixed(0);
                                }),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _amountField(
                                line.quantity,
                                'Quantité en ' + line.unit,
                                validator: _positiveNumber,
                                onEdited: () => _initialLineTouched = true,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _amountField(
                          line.price,
                          'Prix par ${line.unit} ($_currencyLabel)',
                          validator: _positiveNumber,
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            'Sous-total : ${_money(_value(line.quantity) * _value(line.price))}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: navy,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed:
                      lines.length >=
                          widget.products
                              .where((product) => product.quantity > 0)
                              .length
                      ? null
                      : () => setState(() {
                          _initialLineTouched = true;
                          final available = widget.products.firstWhere(
                            (p) =>
                                p.quantity > 0 &&
                                !lines.any((line) => line.product == p),
                          );
                          lines.add(_SaleDraft(available));
                        }),
                  icon: const Icon(Icons.add),
                  label: const Text('Ajouter un produit au panier'),
                ),
              ),
              const SizedBox(height: 12),
              const _SaleSectionHeading(
                icon: Icons.person_outline_rounded,
                title: 'Informations client',
              ),
              _salePanel(
                color: const Color(0xFFF1F8FB),
                child: Column(
                  children: [
                    TextFormField(
                      controller: customer,
                      validator: _customerValidator,
                      decoration: const InputDecoration(
                        labelText: 'Nom du client (obligatoire si crédit)',
                        prefixIcon: Icon(Icons.person_outline_rounded),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: phone,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Téléphone (facultatif)',
                        prefixIcon: Icon(Icons.phone_outlined),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const _SaleSectionHeading(
                icon: Icons.payments_outlined,
                title: 'Paiement et retrait',
              ),
              _salePanel(
                color: const Color(0xFFF0F8F7),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<String>(
                      value: paymentMethod,
                      decoration: const InputDecoration(
                        labelText: 'Mode de paiement',
                        prefixIcon: Icon(Icons.account_balance_wallet_outlined),
                        border: OutlineInputBorder(),
                      ),
                      items: const ['Espèces', 'Mobile Money', 'Banque']
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text(value),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => setState(
                        () => paymentMethod = value ?? paymentMethod,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _amountField(
                      received,
                      'Montant encaissé maintenant ($_currencyLabel)',
                      validator: _paymentValidator,
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile.adaptive(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                      value: pickupLater,
                      onChanged: (value) => setState(() => pickupLater = value),
                      title: const Text('Commande à retirer plus tard'),
                      subtitle: const Text(
                        'Tu pourras confirmer le retrait dans la liste des ventes.',
                      ),
                    ),
                    if (balance > 0) ...[
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: navy,
                          side: const BorderSide(color: Color(0xFFB9C5F3)),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: _chooseDueDate,
                        icon: const Icon(Icons.event_outlined),
                        label: Text(
                          dueDate == null
                              ? 'Ajouter une date de rappel (facultatif)'
                              : 'Rappel : ' + _date(dueDate!),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F2FF),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFDDE1FA)),
                ),
                child: Column(
                  children: [
                    _receiptAmount('Total du panier', total),
                    _receiptAmount('Reçu maintenant', _value(received)),
                    _receiptAmount(
                      'Reste dû',
                      balance,
                      emphasized: balance > 0,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Annuler'),
      ),
      FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF1769E8),
          foregroundColor: Colors.white,
          elevation: 6,
          shadowColor: const Color(0x551769E8),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
        ),
        onPressed: _save,
        icon: const Icon(Icons.check_circle_rounded),
        label: const Text('Enregistrer la vente'),
      ),
    ],
  );

  Widget _salePanel({required Widget child, required Color color}) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFFDCE8EF)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x100F2B68),
          blurRadius: 13,
          offset: Offset(0, 5),
        ),
      ],
    ),
    child: child,
  );
}

class BusinessActivityDialog extends StatefulWidget {
  const BusinessActivityDialog({super.key, required this.businessId});
  final String businessId;

  @override
  State<BusinessActivityDialog> createState() => _BusinessActivityDialogState();
}

class _BusinessActivityDialogState extends State<BusinessActivityDialog> {
  bool loading = true;
  String? error;
  List<Map<String, dynamic>> entries = [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await Supabase.instance.client.rpc(
        'list_business_activity',
        params: {'target_business_id': widget.businessId, 'max_rows': 50},
      );
      entries = (result as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
    } catch (exception) {
      error = "Supabase: $exception";
    }
    if (mounted) setState(() => loading = false);
  }

  String _sectionName(String value) =>
      const {
        'products': 'Produits et stock',
        'sales': 'Ventes',
        'payments': 'Paiements clients',
        'customers': 'Clients',
        'purchases': 'Achats',
        'expenses': 'Dépenses',
        'refunds': 'Remboursements',
        'stocktakes': 'Inventaires',
        'cashMovements': 'Caisse',
      }[value] ??
      value;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Journal d’activité'),
    content: SizedBox(
      width: _dialogWidth(context, 560),
      height: _dialogHeight(context, 430),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Historique des changements enregistrés dans ce commerce.',
          ),
          const SizedBox(height: 6),
          const Text(
            'Les montants et les détails privés ne sont pas affichés.',
            style: TextStyle(color: Colors.black54, fontSize: 13),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : error != null
                ? Center(
                    child: Text(
                      error!,
                      style: const TextStyle(color: Color(0xFFB84A52)),
                    ),
                  )
                : entries.isEmpty
                ? const Center(
                    child: Text('Aucune activité enregistrée pour le moment.'),
                  )
                : ListView.separated(
                    itemCount: entries.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      final sections = (entry['sections'] as List? ?? const [])
                          .map((value) => _sectionName(value.toString()))
                          .join(' • ');
                      final time = DateTime.tryParse(
                        entry['occurred_at']?.toString() ?? '',
                      )?.toLocal();
                      final formattedTime = time == null
                          ? ''
                          : '${time.day.toString().padLeft(2, '0')}/${time.month.toString().padLeft(2, '0')}/${time.year} à ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const CircleAvatar(
                          backgroundColor: Color(0xFFE2F2F0),
                          child: Icon(Icons.edit_note_rounded, color: teal),
                        ),
                        title: Text(
                          entry['actor_email']?.toString() ?? 'Compte inconnu',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '$sections\n${entry['role_label'] ?? 'Membre'} • $formattedTime',
                        ),
                        isThreeLine: true,
                      );
                    },
                  ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: _reload, child: const Text('Actualiser')),
      FilledButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Fermer'),
      ),
    ],
  );
}

class TeamManagementDialog extends StatefulWidget {
  const TeamManagementDialog({
    super.key,
    required this.businessId,
    required this.managerRole,
    required this.languageCode,
  });
  final String businessId;
  final String managerRole;
  final String languageCode;

  @override
  State<TeamManagementDialog> createState() => _TeamManagementDialogState();
}

class _TeamManagementDialogState extends State<TeamManagementDialog> {
  final email = TextEditingController();
  final formKey = GlobalKey<FormState>();
  String role = 'staff';
  bool loading = true;
  bool saving = false;
  String? error;
  String? message;
  String? _preparedInviteEmail;
  String? _preparedInviteRole;
  String? _preparedInviteStatus;
  String? _preparedInviteLink;
  String? _removingEmail;
  List<Map<String, dynamic>> entries = [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    email.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await Supabase.instance.client.rpc(
        'list_business_access',
        params: {'target_business_id': widget.businessId},
      );
      entries = (result as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
    } catch (exception) {
      debugPrint('Chargement de l’équipe BizGestion impossible : $exception');
      error = "Supabase: $exception";
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _invite() async {
    if (!formKey.currentState!.validate()) return;
    setState(() {
      saving = true;
      error = null;
      message = null;
      _preparedInviteLink = null;
    });
    try {
      final inviteEmail = email.text.trim().toLowerCase();
      final status = (await Supabase.instance.client.rpc(
        'create_business_invitation',
        params: {
          'target_business_id': widget.businessId,
          'invite_email': inviteEmail,
          'invite_role': role,
        },
      )).toString();
      if (!{
        'member_added',
        'account_waiting_confirmation',
        'invitation_pending',
      }.contains(status)) {
        throw StateError('Réponse d’invitation inattendue.');
      }
      final currentUri = Uri.base;
      final localHosts = {'localhost', '127.0.0.1', '0.0.0.0'};
      final publicAppUri =
          currentUri.hasAuthority &&
              currentUri.scheme.startsWith('http') &&
              !localHosts.contains(currentUri.host)
          ? currentUri
          : Uri.parse('https://peaceful-seahorse-c8bdc5.netlify.app');
      final inviteLink = publicAppUri.replace(
        path: '/',
        queryParameters: {
          'invite': inviteEmail,
          'create': status == 'invitation_pending' ? '1' : '0',
          'lang': widget.languageCode,
        },
      );
      _preparedInviteEmail = inviteEmail;
      _preparedInviteRole = _teamRoleLabel(role);
      _preparedInviteStatus = status;
      _preparedInviteLink = inviteLink.toString();
      email.clear();
      message = switch (status) {
        'member_added' => _tr(
          'Accès de $inviteEmail prêt. Aucun courriel envoyé : copie le message ci-dessous et partage-le.',
          'Access for $inviteEmail is ready. No email was sent; copy and share the message below.',
        ),
        'account_waiting_confirmation' => _tr(
          'Accès préparé pour $inviteEmail. La personne doit confirmer son adresse avant de se connecter.',
          'Access is ready for $inviteEmail. They must confirm their email address before signing in.',
        ),
        _ => _tr(
          'Invitation préparée pour $inviteEmail. Copie le message et partage-le par WhatsApp ou un autre moyen.',
          'Invitation prepared for $inviteEmail. Copy the message and share it by WhatsApp or another method.',
        ),
      };
      await _reload();
    } catch (exception) {
      final details = exception.toString();
      error = details.contains('NOT_FOUND') || details.contains('PGRST202')
          ? 'Le script d’accès équipe doit être exécuté dans Supabase avant de préparer une invitation.'
          : 'Supabase : $exception';
    }
    if (mounted) setState(() => saving = false);
  }

  Future<void> _removeAccess(Map<String, dynamic> entry) async {
    final targetEmail = entry['email']?.toString().trim() ?? '';
    if (targetEmail.isEmpty) return;
    final targetRole = entry['role']?.toString() ?? 'staff';
    final isPending = entry['status'] == 'Invitation en attente';
    final targetLabel = targetRole == 'admin' ? 'administrateur' : 'employé';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          isPending ? 'Annuler cette invitation ?' : 'Retirer cet accès ?',
        ),
        content: Text(
          isPending
              ? 'L’invitation envoyée à $targetEmail sera annulée.'
              : 'Le compte $targetEmail ne pourra plus accéder à ce commerce. Son compte BizGestion personnel restera intact.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Garder'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFB84A52),
            ),
            child: Text(isPending ? 'Annuler l’invitation' : 'Retirer l’accès'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _removingEmail = targetEmail;
      error = null;
      message = null;
    });
    try {
      await Supabase.instance.client.rpc(
        'revoke_business_access',
        params: {
          'target_business_id': widget.businessId,
          'target_email': targetEmail,
        },
      );
      message = isPending
          ? 'Invitation annulée pour $targetEmail.'
          : 'Accès de l’$targetLabel retiré pour $targetEmail.';
      await _reload();
    } catch (exception) {
      debugPrint('Retrait d’accès BizGestion impossible : $exception');
      error = 'Impossible de retirer cet accès. Détail Supabase : $exception';
    }
    if (mounted) setState(() => _removingEmail = null);
  }

  Future<void> _copyInvitation() async {
    final inviteEmail = _preparedInviteEmail;
    final inviteLink = _preparedInviteLink;
    if (inviteEmail == null || inviteLink == null) return;
    final instruction = _activeLanguageCode == 'en'
        ? switch (_preparedInviteStatus) {
            'member_added' =>
              'Your access is ready. Open the link and sign in with this email address: $inviteEmail.',
            'account_waiting_confirmation' =>
              'Your account exists, but your email address must be confirmed. Confirm it, then open the link and sign in with: $inviteEmail.',
            _ =>
              'Open the link and create your BizGestion account with this email address: $inviteEmail. Access to the business will activate automatically after confirmation.',
          }
        : switch (_preparedInviteStatus) {
            'member_added' =>
              'Ton accès est prêt. Ouvre le lien puis connecte-toi avec cette adresse e-mail : $inviteEmail.',
            'account_waiting_confirmation' =>
              'Ton compte existe déjà, mais l’adresse e-mail doit être confirmée. Termine cette confirmation, puis ouvre le lien et connecte-toi avec : $inviteEmail.',
            _ =>
              'Ouvre le lien et crée ton compte BizGestion avec cette adresse e-mail : $inviteEmail. L’accès au commerce sera activé automatiquement après confirmation.',
          };
    final text = _activeLanguageCode == 'en'
        ? 'Hello,\n\nI invite you to join my business on BizGestion as ${_preparedInviteRole?.toLowerCase() ?? 'a member'}.\n\n$instruction\n\n$inviteLink\n\nSee you soon.'
        : 'Bonjour,\n\nJe t’invite à rejoindre mon commerce sur BizGestion comme ${_preparedInviteRole?.toLowerCase() ?? 'membre'}.\n\n$instruction\n\n$inviteLink\n\nÀ bientôt.';
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _tr(
            'Message d’invitation copié. Tu peux le coller dans WhatsApp ou un e-mail.',
            'Invitation message copied. You can paste it into WhatsApp or an email.',
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(_tr('Équipe du commerce', 'Business team')),
    content: SizedBox(
      width: _dialogWidth(context, 540),
      child: SingleChildScrollView(
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _tr(
                  'Prépare un accès sans frais d’envoi. Après la création, copie le message et partage-le par WhatsApp ou un autre moyen.',
                  'Set up access without email fees. Afterward, copy the message and share it by WhatsApp or another method.',
                ),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: email,
                keyboardType: TextInputType.emailAddress,
                validator: (value) {
                  final text = (value ?? '').trim();
                  return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(text)
                      ? null
                      : _tr(
                          'Saisis une adresse e-mail valide.',
                          'Enter a valid email address.',
                        );
                },
                decoration: InputDecoration(
                  labelText: _tr(
                    'Adresse e-mail du membre',
                    'Member email address',
                  ),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: role,
                decoration: InputDecoration(
                  labelText: _tr('Accès', 'Access'),
                  border: OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem(
                    value: 'staff',
                    child: Text(_tr('Employé', 'Staff')),
                  ),
                  DropdownMenuItem(
                    value: 'admin',
                    child: Text(_tr('Administrateur', 'Administrator')),
                  ),
                ],
                onChanged: (value) => setState(() => role = value ?? role),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: saving ? null : _invite,
                icon: const Icon(Icons.person_add_alt_1),
                label: Text(
                  saving
                      ? _tr('Préparation…', 'Preparing…')
                      : _tr('Préparer l’invitation', 'Prepare invitation'),
                ),
              ),
              if (message != null) ...[
                const SizedBox(height: 10),
                Text(message!, style: const TextStyle(color: teal)),
                if (_preparedInviteEmail != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _copyInvitation,
                      icon: const Icon(Icons.copy_rounded),
                      label: Text(
                        _tr(
                          'Copier le message d’invitation',
                          'Copy invitation message',
                        ),
                      ),
                    ),
                  ),
              ],
              if (error != null) ...[
                const SizedBox(height: 10),
                Text(error!, style: const TextStyle(color: Color(0xFFB84A52))),
              ],
              const SizedBox(height: 18),
              Text(
                _tr('Membres et invitations', 'Members and invitations'),
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              if (loading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (entries.isEmpty)
                Text(
                  _tr(
                    'Aucun membre ni invitation pour le moment.',
                    'No members or invitations yet.',
                  ),
                )
              else
                ...entries.map((entry) {
                  final memberRole = entry['role']?.toString() ?? 'staff';
                  final canRemove =
                      memberRole != 'owner' &&
                      (widget.managerRole == 'owner' || memberRole == 'staff');
                  final memberEmail = entry['email']?.toString() ?? '';
                  final isRemoving = _removingEmail == memberEmail;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      entry['status'] == 'Membre'
                          ? Icons.person_outline
                          : Icons.mail_outline,
                      color: teal,
                    ),
                    title: Text(memberEmail),
                    subtitle: Text(
                      '${_teamRoleLabel(memberRole)} • ${_teamStatusLabel(entry['status']?.toString() ?? '')}',
                    ),
                    trailing: canRemove
                        ? IconButton(
                            tooltip: entry['status'] == 'Invitation en attente'
                                ? _tr(
                                    'Annuler l’invitation',
                                    'Cancel invitation',
                                  )
                                : _tr('Retirer l’accès', 'Remove access'),
                            onPressed: isRemoving || saving
                                ? null
                                : () => _removeAccess(entry),
                            icon: isRemoving
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(
                                    Icons.person_remove_outlined,
                                    color: Color(0xFFB84A52),
                                  ),
                          )
                        : null,
                  );
                }),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(onPressed: _reload, child: Text(_tr('Actualiser', 'Refresh'))),
      FilledButton(
        onPressed: () => Navigator.pop(context),
        child: Text(_tr('Fermer', 'Close')),
      ),
    ],
  );
}

class PurchaseContent extends StatelessWidget {
  const PurchaseContent({
    super.key,
    required this.products,
    required this.purchases,
    required this.suppliers,
    required this.onAddProduct,
    required this.onSavePurchase,
    required this.onSaveSupplier,
  });

  final List<Product> products;
  final List<PurchaseRecord> purchases;
  final List<SupplierRecord> suppliers;
  final VoidCallback onAddProduct;
  final Future<void> Function(List<PurchaseRecord>) onSavePurchase;
  final ValueChanged<SupplierRecord> onSaveSupplier;

  Future<void> _editSupplier(
    BuildContext context, [
    SupplierRecord? supplier,
  ]) async {
    final result = await showDialog<SupplierRecord>(
      context: context,
      builder: (_) => SupplierDialog(supplier: supplier),
    );
    if (result != null) onSaveSupplier(result);
  }

  Future<void> _showSupplierHistory(
    BuildContext context,
    SupplierRecord supplier,
    List<PurchaseRecord> history,
  ) => showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final total = history.fold<double>(
        0,
        (sum, item) => sum + item.totalCost,
      );
      return AlertDialog(
        title: Text(supplier.name),
        content: SizedBox(
          width: _dialogWidth(dialogContext, 560),
          child: ListView(
            shrinkWrap: true,
            children: [
              if (supplier.phone.isNotEmpty)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.phone_outlined),
                  title: Text(supplier.phone),
                ),
              if (supplier.email.isNotEmpty)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.email_outlined),
                  title: Text(supplier.email),
                ),
              if (supplier.address.isNotEmpty)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.place_outlined),
                  title: Text(supplier.address),
                ),
              if (supplier.notes.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(supplier.notes),
                ),
              const Divider(),
              Text(
                'Historique • ${history.length} ligne(s) • ${_money(total)}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              if (history.isEmpty)
                const Text('Aucun achat enregistré pour ce fournisseur.'),
              ...history.map(
                (purchase) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.shopping_bag_outlined, color: teal),
                  title: Text(purchase.product.name),
                  subtitle: Text(
                    '${_date(purchase.date)} • ${_quantity(purchase.quantity)} ${purchase.product.unit} × ${_money(purchase.unitPrice)}\nFrais : ${_money(purchase.tripExpenses)} • ${purchase.paymentMethod}',
                  ),
                  isThreeLine: true,
                  trailing: Text(
                    _money(purchase.totalCost),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Navigator.pop(dialogContext);
              _editSupplier(context, supplier);
            },
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Modifier la fiche'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Fermer'),
          ),
        ],
      );
    },
  );

  Future<void> _newPurchase(BuildContext context) async {
    if (products.isEmpty) {
      final createProduct = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Aucun produit dans le stock'),
          content: const Text(
            'Ajoute d’abord un produit pour enregistrer son approvisionnement.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Plus tard'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Créer un produit'),
            ),
          ],
        ),
      );
      if (createProduct == true) onAddProduct();
      return;
    }

    final supplierNames = <String>{
      ...suppliers.map((item) => item.name),
      ...purchases
          .map((item) => item.supplier.trim())
          .where((name) => name.isNotEmpty),
    }.toList();
    final batch = await showDialog<List<PurchaseRecord>>(
      context: context,
      builder: (_) =>
          AddPurchaseDialog(products: products, suppliers: supplierNames),
    );
    if (batch != null && batch.isNotEmpty) await onSavePurchase(batch);
  }

  @override
  Widget build(BuildContext context) {
    final goodsTotal = purchases.fold(
      0.0,
      (sum, item) => sum + item.quantity * item.unitPrice,
    );
    final tripTotal = purchases.fold(
      0.0,
      (sum, item) => sum + item.tripExpenses,
    );
    final acquisitionTotal = purchases.fold(
      0.0,
      (sum, item) => sum + item.totalCost,
    );
    final transportTotal = purchases.fold(
      0.0,
      (sum, item) => sum + item.transport,
    );
    final mealsTotal = purchases.fold(0.0, (sum, item) => sum + item.meals);
    final handlingTotal = purchases.fold(
      0.0,
      (sum, item) => sum + item.handling,
    );
    final otherTotal = purchases.fold(
      0.0,
      (sum, item) => sum + item.otherExpenses,
    );
    final purchasesBySupplier = <String, List<PurchaseRecord>>{};
    for (final purchase in purchases) {
      final supplierName = purchase.supplier.trim();
      if (supplierName.isEmpty) continue;
      final key = supplierName.toLowerCase();
      purchasesBySupplier.putIfAbsent(key, () => []).add(purchase);
    }
    final supplierGroups = purchasesBySupplier.values.toList()
      ..sort(
        (a, b) => b
            .fold<double>(0, (sum, item) => sum + item.totalCost)
            .compareTo(a.fold<double>(0, (sum, item) => sum + item.totalCost)),
      );
    final supplierEntries = <SupplierRecord>[
      ...suppliers,
      ...supplierGroups
          .where(
            (group) => !suppliers.any(
              (supplier) =>
                  supplier.name.toLowerCase() ==
                  group.first.supplier.trim().toLowerCase(),
            ),
          )
          .map((group) => SupplierRecord(name: group.first.supplier.trim())),
    ];
    return ListView(
      padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 600 ? 16 : 26),
      children: [
        _BizPageHero(
          title: _tr('Achats et approvisionnements', 'Purchases and supplies'),
          subtitle: _tr(
            'Enregistre les achats, les quantités et les frais du trajet.',
            'Record purchases, quantities, and delivery expenses.',
          ),
          icon: Icons.shopping_bag_rounded,
          action: FilledButton.icon(
            onPressed: () => _newPurchase(context),
            icon: const Icon(Icons.add),
            label: Text(_tr('Nouvel achat', 'New purchase')),
          ),
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: 250,
              child: SummaryCard(
                title: _tr('Marchandises achetées', 'Goods purchased'),
                value: _money(goodsTotal),
                icon: Icons.inventory_2_outlined,
                color: teal,
              ),
            ),
            SizedBox(
              width: 250,
              child: SummaryCard(
                title: _tr('Frais d’approvisionnement', 'Supply expenses'),
                value: _money(tripTotal),
                icon: Icons.local_shipping_outlined,
                color: const Color(0xFFD88931),
              ),
            ),
            SizedBox(
              width: 250,
              child: SummaryCard(
                title: _tr(
                  'Coût total d’acquisition',
                  'Total acquisition cost',
                ),
                value: _money(acquisitionTotal),
                icon: Icons.account_balance_wallet_outlined,
                color: const Color(0xFF527ACB),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _tr(
                    'Répartition des frais du trajet',
                    'Delivery cost breakdown',
                  ),
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: navy,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _purchaseCostChip(
                      Icons.local_shipping_outlined,
                      _tr('Transport', 'Transport'),
                      transportTotal,
                      const Color(0xFF527ACB),
                    ),
                    _purchaseCostChip(
                      Icons.restaurant_outlined,
                      _tr('Repas', 'Meals'),
                      mealsTotal,
                      const Color(0xFFD88931),
                    ),
                    _purchaseCostChip(
                      Icons.front_hand_outlined,
                      _tr('Manutention', 'Handling'),
                      handlingTotal,
                      teal,
                    ),
                    _purchaseCostChip(
                      Icons.more_horiz,
                      _tr('Autres', 'Other'),
                      otherTotal,
                      const Color(0xFF7A63B7),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: Text(
                _tr('Fournisseurs suivis', 'Suppliers'),
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: navy,
                ),
              ),
            ),
            Chip(label: Text('${supplierEntries.length}')),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: () => _editSupplier(context),
              icon: const Icon(Icons.person_add_alt_1_outlined),
              label: Text(_tr('Ajouter', 'Add')),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (supplierGroups.isEmpty && suppliers.isEmpty)
          Card(
            color: Colors.white,
            child: Padding(
              padding: EdgeInsets.all(18),
              child: Text(
                _tr(
                  'Ajoute le nom du fournisseur lors d’un prochain approvisionnement pour retrouver ici l’historique de tes achats.',
                  'Enter a supplier name during your next purchase to see its purchase history here.',
                ),
              ),
            ),
          ),
        ...supplierEntries.map((supplier) {
          final group = purchases
              .where(
                (item) =>
                    item.supplier.trim().toLowerCase() ==
                    supplier.name.toLowerCase(),
              )
              .toList();
          final supplierName = supplier.name;
          final total = group.fold<double>(
            0,
            (sum, item) => sum + item.totalCost,
          );
          final latest = group.isEmpty
              ? null
              : group
                    .map((item) => item.date)
                    .reduce((a, b) => a.isAfter(b) ? a : b);
          final productCount = group
              .map((item) => item.product.name.toLowerCase())
              .toSet()
              .length;
          return Card(
            color: Colors.white,
            child: ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFE8EAFE),
                child: Icon(Icons.storefront_outlined, color: navy),
              ),
              title: Text(
                supplierName,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                '${group.length} ${_tr('ligne(s) d’achat', 'purchase line(s)')} • $productCount ${_tr('produit(s)', 'product(s)')}${latest == null ? '' : ' • ${_tr('Dernier achat : ', 'Last purchase: ')}${_date(latest)}'}${supplier.phone.isEmpty ? '' : '\n${supplier.phone}'}',
              ),
              isThreeLine: true,
              onTap: () => _showSupplierHistory(context, supplier, group),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _money(total),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: navy,
                    ),
                  ),
                  IconButton(
                    tooltip: _tr('Modifier la fiche', 'Edit supplier'),
                    onPressed: () => _editSupplier(context, supplier),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                ],
              ),
            ),
          );
        }),
        const SizedBox(height: 12),
        if (purchases.isEmpty)
          Card(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                children: [
                  Icon(Icons.local_shipping_outlined, size: 42, color: teal),
                  SizedBox(height: 12),
                  Text(
                    _tr(
                      'Aucun achat enregistré pour le moment.',
                      'No purchases recorded yet.',
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    _tr(
                      'Les frais de transport, repas et manutention seront intégrés au coût moyen du produit.',
                      'Transport, meals and handling costs will be included in the product average cost.',
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          )
        else
          ...purchases.map(
            (purchase) => Card(
              color: Colors.white,
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFE2F2F0),
                  child: Icon(Icons.shopping_bag_outlined, color: teal),
                ),
                title: Text(
                  purchase.product.name,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  _date(purchase.date) +
                      (purchase.supplier.isEmpty
                          ? ''
                          : ' • ${_tr('Fournisseur : ', 'Supplier: ')}' +
                                purchase.supplier) +
                      '\n' +
                      _quantity(purchase.quantity) +
                      ' ' +
                      _unitLabel(purchase.product.unit) +
                      ' × ' +
                      _money(purchase.unitPrice) +
                      '\n${_tr('Frais de trajet : ', 'Delivery expenses: ')}' +
                      _money(purchase.tripExpenses) +
                      ' • ' +
                      purchase.paymentMethod,
                ),
                isThreeLine: true,
                trailing: Text(
                  _money(purchase.totalCost),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: ink,
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 10),
        Text(
          _tr(
            'Les frais communs d’un approvisionnement sont répartis entre les produits selon leur part dans le montant des achats.',
            'Shared supply costs are allocated to products according to each product’s share of the purchase total.',
          ),
          style: TextStyle(fontSize: 12, color: Colors.black45),
        ),
      ],
    );
  }

  Widget _purchaseCostChip(
    IconData icon,
    String label,
    double amount,
    Color color,
  ) => Container(
    constraints: const BoxConstraints(minWidth: 150),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
            Text(
              _money(amount),
              style: TextStyle(fontWeight: FontWeight.bold, color: color),
            ),
          ],
        ),
      ],
    ),
  );
}

class SupplierDialog extends StatefulWidget {
  const SupplierDialog({super.key, this.supplier});
  final SupplierRecord? supplier;

  @override
  State<SupplierDialog> createState() => _SupplierDialogState();
}

class _SupplierDialogState extends State<SupplierDialog> {
  final formKey = GlobalKey<FormState>();
  late final name = TextEditingController(text: widget.supplier?.name ?? '');
  late final phone = TextEditingController(text: widget.supplier?.phone ?? '');
  late final email = TextEditingController(text: widget.supplier?.email ?? '');
  late final address = TextEditingController(
    text: widget.supplier?.address ?? '',
  );
  late final notes = TextEditingController(text: widget.supplier?.notes ?? '');

  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    email.dispose();
    address.dispose();
    notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.supplier == null ? 'Nouveau fournisseur' : 'Fiche fournisseur',
    ),
    content: SizedBox(
      width: _dialogWidth(context, 480),
      child: SingleChildScrollView(
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: name,
                readOnly: widget.supplier != null,
                validator: (value) => (value ?? '').trim().isEmpty
                    ? 'Saisis le nom du fournisseur.'
                    : null,
                decoration: const InputDecoration(
                  labelText: 'Nom du fournisseur',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Téléphone (facultatif)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'E-mail (facultatif)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.email_outlined),
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: address,
                decoration: const InputDecoration(
                  labelText: 'Adresse (facultatif)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.place_outlined),
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: notes,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Notes',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Annuler'),
      ),
      FilledButton(
        onPressed: () {
          if (!formKey.currentState!.validate()) return;
          Navigator.pop(
            context,
            SupplierRecord(
              name: name.text.trim(),
              phone: phone.text.trim(),
              email: email.text.trim(),
              address: address.text.trim(),
              notes: notes.text.trim(),
            ),
          );
        },
        child: const Text('Enregistrer'),
      ),
    ],
  );
}

class AddPurchaseDialog extends StatefulWidget {
  const AddPurchaseDialog({
    super.key,
    required this.products,
    required this.suppliers,
  });
  final List<Product> products;
  final List<String> suppliers;

  @override
  State<AddPurchaseDialog> createState() => _AddPurchaseDialogState();
}

class _PurchaseDraft {
  _PurchaseDraft(Product product)
    : product = product,
      productSearch = TextEditingController(text: product.name);
  Product product;
  final TextEditingController productSearch;
  final quantity = TextEditingController(text: '1');
  final unitPrice = TextEditingController();
  void dispose() {
    productSearch.dispose();
    quantity.dispose();
    unitPrice.dispose();
  }
}

class _AddPurchaseDialogState extends State<AddPurchaseDialog> {
  final formKey = GlobalKey<FormState>();
  final supplier = TextEditingController();
  final transport = TextEditingController(text: '0');
  final meals = TextEditingController(text: '0');
  final handling = TextEditingController(text: '0');
  final other = TextEditingController(text: '0');
  String paymentMethod = 'Espèces';
  late final List<_PurchaseDraft> lines = [
    _PurchaseDraft(widget.products.first),
  ];

  @override
  void dispose() {
    supplier.dispose();
    for (final line in lines) {
      line.dispose();
    }
    transport.dispose();
    meals.dispose();
    handling.dispose();
    other.dispose();
    super.dispose();
  }

  double _read(TextEditingController c) =>
      double.parse(c.text.trim().replaceAll(',', '.'));

  String? _validate(String? value, {bool positive = false}) {
    final number = double.tryParse((value ?? '').trim().replaceAll(',', '.'));
    if (number == null || number < 0 || (positive && number == 0)) {
      return positive
          ? 'Saisis un nombre supérieur à zéro.'
          : 'Saisis un montant valide.';
    }
    return null;
  }

  Widget _field(
    TextEditingController c,
    String label, {
    bool positive = false,
  }) => TextFormField(
    controller: c,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    validator: (value) => _validate(value, positive: positive),
    onChanged: (_) => setState(() {}),
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
    ),
  );

  double _value(TextEditingController c) =>
      double.tryParse(c.text.replaceAll(',', '.')) ?? 0;

  double get _goodsTotal => lines.fold(
    0.0,
    (sum, line) => sum + _value(line.quantity) * _value(line.unitPrice),
  );

  double get _tripExpenses {
    double value(TextEditingController c) =>
        double.tryParse(c.text.replaceAll(',', '.')) ?? 0;
    return value(transport) + value(meals) + value(handling) + value(other);
  }

  void _save() {
    if (!formKey.currentState!.validate()) return;
    final totalGoods = _goodsTotal;
    final purchases = lines.map((line) {
      final ratio =
          (_value(line.quantity) * _value(line.unitPrice)) / totalGoods;
      return PurchaseRecord(
        product: line.product,
        supplier: supplier.text.trim(),
        quantity: _read(line.quantity),
        unitPrice: _read(line.unitPrice),
        transport: _read(transport) * ratio,
        meals: _read(meals) * ratio,
        handling: _read(handling) * ratio,
        otherExpenses: _read(other) * ratio,
        date: DateTime.now(),
        paymentMethod: paymentMethod,
      );
    }).toList();
    Navigator.pop(context, purchases);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Nouvel approvisionnement'),
    content: SizedBox(
      width: _dialogWidth(context, 640),
      child: SingleChildScrollView(
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              Autocomplete<String>(
                optionsBuilder: (value) {
                  final query = _normalizeStockSearch(value.text);
                  if (query.isEmpty) return widget.suppliers;
                  return widget.suppliers.where(
                    (name) => _normalizeStockSearch(name).contains(query),
                  );
                },
                onSelected: (value) => supplier.text = value,
                fieldViewBuilder:
                    (context, controller, focusNode, onFieldSubmitted) {
                      if (supplier.text.isNotEmpty && controller.text.isEmpty)
                        controller.text = supplier.text;
                      return TextFormField(
                        controller: controller,
                        focusNode: focusNode,
                        onChanged: (value) => supplier.text = value,
                        decoration: const InputDecoration(
                          labelText: 'Fournisseur (facultatif)',
                          border: OutlineInputBorder(),
                          suffixIcon: Icon(Icons.arrow_drop_down),
                        ),
                      );
                    },
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: paymentMethod,
                decoration: const InputDecoration(
                  labelText: 'Mode de paiement',
                  border: OutlineInputBorder(),
                ),
                items:
                    const [
                          'Espèces',
                          'Mobile Money',
                          'Banque',
                          'Crédit fournisseur',
                        ]
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value),
                          ),
                        )
                        .toList(),
                onChanged: (value) =>
                    setState(() => paymentMethod = value ?? paymentMethod),
              ),
              const SizedBox(height: 16),
              const Text(
                'Produits achetés',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ...lines.asMap().entries.map((entry) {
                final index = entry.key;
                final line = entry.value;
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Autocomplete<Product>(
                                displayStringForOption: (product) =>
                                    product.name,
                                optionsBuilder: (value) {
                                  final query = _normalizeStockSearch(
                                    value.text,
                                  );
                                  final available = widget.products.where(
                                    (product) => !lines.asMap().entries.any(
                                      (other) =>
                                          other.key != index &&
                                          other.value.product == product,
                                    ),
                                  );
                                  if (query.isEmpty) return available;
                                  return available.where(
                                    (product) =>
                                        _matchesStockSearch(product, query),
                                  );
                                },
                                onSelected: (product) => setState(() {
                                  line.product = product;
                                  line.productSearch.text = product.name;
                                }),
                                fieldViewBuilder:
                                    (
                                      context,
                                      controller,
                                      focusNode,
                                      onFieldSubmitted,
                                    ) {
                                      if (controller.text.isEmpty) {
                                        controller.text =
                                            line.productSearch.text;
                                      }
                                      return TextField(
                                        controller: controller,
                                        focusNode: focusNode,
                                        onChanged: (value) =>
                                            line.productSearch.text = value,
                                        decoration: InputDecoration(
                                          labelText: 'Rechercher un produit',
                                          hintText: 'Nom ou code-barres',
                                          prefixIcon: const Icon(Icons.search),
                                          border: const OutlineInputBorder(),
                                          filled: true,
                                          fillColor: const Color(0xFFF0F5FF),
                                        ),
                                      );
                                    },
                                optionsViewBuilder:
                                    (context, onSelected, options) => Align(
                                      alignment: Alignment.topLeft,
                                      child: Material(
                                        elevation: 8,
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(12),
                                        child: ConstrainedBox(
                                          constraints: const BoxConstraints(
                                            maxHeight: 260,
                                            maxWidth: 520,
                                          ),
                                          child: ListView.builder(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 6,
                                            ),
                                            shrinkWrap: true,
                                            itemCount: options.length,
                                            itemBuilder: (context, optionIndex) {
                                              final product = options.elementAt(
                                                optionIndex,
                                              );
                                              return ListTile(
                                                dense: true,
                                                leading: const Icon(
                                                  Icons.inventory_2_outlined,
                                                  color: Color(0xFF315FCE),
                                                ),
                                                title: Text(
                                                  product.name,
                                                  style: const TextStyle(
                                                    color: Color(0xFF173A8A),
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                                subtitle: Text(
                                                  '${_quantity(product.quantity)} ${product.unit}' +
                                                      (product.barcode.isEmpty
                                                          ? ''
                                                          : ' • ${product.barcode}'),
                                                ),
                                                onTap: () =>
                                                    onSelected(product),
                                              );
                                            },
                                          ),
                                        ),
                                      ),
                                    ),
                              ),
                            ),
                            IconButton(
                              onPressed: lines.length == 1
                                  ? null
                                  : () => setState(() {
                                      lines.removeAt(index).dispose();
                                    }),
                              icon: const Icon(Icons.delete_outline),
                              tooltip: 'Retirer ce produit',
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: _field(
                                line.quantity,
                                'Quantité en ' + line.product.unit,
                                positive: true,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _field(
                                line.unitPrice,
                                'Prix par ${line.product.unit} ($_currencyLabel)',
                                positive: true,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: lines.length >= widget.products.length
                      ? null
                      : () => setState(() {
                          final available = widget.products
                              .where(
                                (p) => !lines.any((line) => line.product == p),
                              )
                              .first;
                          lines.add(_PurchaseDraft(available));
                        }),
                  icon: const Icon(Icons.add),
                  label: const Text('Ajouter un produit à cet achat'),
                ),
              ),
              const SizedBox(height: 18),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Frais du trajet',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 10),
              _field(transport, 'Chauffeur / transport ($_currencyLabel)'),
              const SizedBox(height: 10),
              _field(meals, 'Repas ($_currencyLabel)'),
              const SizedBox(height: 10),
              _field(handling, 'Pousse-pousse / manutention ($_currencyLabel)'),
              const SizedBox(height: 10),
              _field(other, 'Autres frais ($_currencyLabel)'),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF5F3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Marchandises : ' +
                      _money(_goodsTotal) +
                      '\nFrais du trajet : ' +
                      _money(_tripExpenses) +
                      '\nCoût total estimé : ' +
                      _money(_goodsTotal + _tripExpenses),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: teal,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Annuler'),
      ),
      FilledButton(
        onPressed: _save,
        child: const Text('Enregistrer l’approvisionnement'),
      ),
    ],
  );
}

String _date(DateTime date) => _activeCountryCode == 'US'
    ? '${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}/${date.year}'
    : '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
String _dateTime(DateTime date) =>
    '${_date(date)} • ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

int? _daysUntilExpiry(Product product) {
  final date = product.expirationDate;
  if (date == null) return null;
  final today = DateTime.now();
  return DateTime(
    date.year,
    date.month,
    date.day,
  ).difference(DateTime(today.year, today.month, today.day)).inDays;
}

Widget _expirationDatePicker(
  BuildContext context,
  DateTime? selected,
  ValueChanged<DateTime?> onChanged,
) => Row(
  children: [
    Expanded(
      child: OutlinedButton.icon(
        onPressed: () async {
          final today = DateTime.now();
          final value = await showDatePicker(
            context: context,
            initialDate: selected ?? today,
            firstDate: DateTime(today.year - 10),
            lastDate: DateTime(today.year + 20),
            helpText: 'Date de péremption',
            cancelText: 'Annuler',
            confirmText: 'Choisir',
          );
          if (value != null) onChanged(value);
        },
        icon: const Icon(Icons.event_outlined),
        label: Text(
          selected == null
              ? 'Ajouter une date de péremption (facultatif)'
              : 'Péremption : ${_date(selected)}',
        ),
      ),
    ),
    if (selected != null)
      IconButton(
        tooltip: 'Retirer la date',
        onPressed: () => onChanged(null),
        icon: const Icon(Icons.close),
      ),
  ],
);

class StocktakeRecord {
  StocktakeRecord({
    String? recordId,
    required this.product,
    required this.previousQuantity,
    required this.countedQuantity,
    required this.date,
    required this.reason,
  }) : recordId = recordId ?? _newRecordId();
  final String recordId;
  final Product product;
  final double previousQuantity;
  final double countedQuantity;
  final DateTime date;
  final String reason;
  double get difference => countedQuantity - previousQuantity;
  Map<String, dynamic> toJson() => {
    'recordId': recordId,
    'product': product.toJson(includeRecordId: false),
    'previousQuantity': previousQuantity,
    'countedQuantity': countedQuantity,
    'date': date.toIso8601String(),
    'reason': reason,
  };
  factory StocktakeRecord.fromJson(Map<String, dynamic> json) =>
      StocktakeRecord(
        recordId: json['recordId'] as String?,
        product: Product.fromJson(Map<String, dynamic>.from(json['product'])),
        previousQuantity: (json['previousQuantity'] as num).toDouble(),
        countedQuantity: (json['countedQuantity'] as num).toDouble(),
        date: DateTime.parse(json['date'] as String),
        reason: json['reason'] as String,
      );
}

class StocktakeDialog extends StatefulWidget {
  const StocktakeDialog({super.key, required this.products});
  final List<Product> products;
  @override
  State<StocktakeDialog> createState() => _StocktakeDialogState();
}

class _StocktakeLine {
  _StocktakeLine(this.product)
    : counted = TextEditingController(text: _quantity(product.quantity));
  final Product product;
  final TextEditingController counted;
}

class _StocktakeDialogState extends State<StocktakeDialog> {
  final formKey = GlobalKey<FormState>();
  final reason = TextEditingController();
  late final lines = widget.products.map(_StocktakeLine.new).toList();
  @override
  void dispose() {
    reason.dispose();
    for (final line in lines) {
      line.counted.dispose();
    }
    super.dispose();
  }

  void _save() {
    if (!formKey.currentState!.validate()) return;
    final now = DateTime.now();
    final adjustments = lines
        .map(
          (line) => StocktakeRecord(
            product: line.product,
            previousQuantity: line.product.quantity,
            countedQuantity: double.parse(
              line.counted.text.trim().replaceAll(',', '.'),
            ),
            date: now,
            reason: reason.text.trim(),
          ),
        )
        .where((item) => item.difference.abs() > 0.000001)
        .toList();
    Navigator.pop(context, adjustments);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Inventaire physique'),
    content: SizedBox(
      width: _dialogWidth(context, 620),
      height: _dialogHeight(context, 480),
      child: Form(
        key: formKey,
        child: Column(
          children: [
            const Text(
              'Compte les quantités réellement présentes. Seuls les écarts seront enregistrés comme corrections.',
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: reason,
              decoration: const InputDecoration(
                labelText: 'Motif (facultatif)',
                hintText: 'Ex. : inventaire de fin de mois',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                children: lines
                    .map(
                      (line) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                line.product.name +
                                    '\nThéorique : ' +
                                    _quantity(line.product.quantity) +
                                    ' ' +
                                    line.product.unit,
                              ),
                            ),
                            SizedBox(
                              width: 145,
                              child: TextFormField(
                                controller: line.counted,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                validator: (v) {
                                  final n = double.tryParse(
                                    (v ?? '').trim().replaceAll(',', '.'),
                                  );
                                  return n == null || n < 0
                                      ? 'Nombre ≥ 0 requis'
                                      : null;
                                },
                                decoration: InputDecoration(
                                  labelText:
                                      'Compté (' + line.product.unit + ')',
                                  border: const OutlineInputBorder(),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Annuler'),
      ),
      FilledButton(onPressed: _save, child: const Text('Valider l’inventaire')),
    ],
  );
}

class _GuideSection extends StatelessWidget {
  const _GuideSection({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    color: Colors.white,
    elevation: 2,
    shadowColor: const Color(0x171B2C73),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: const BorderSide(color: Color(0xFFE5EAF2)),
    ),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFE9F5F4),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: teal),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: navy,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  body,
                  style: const TextStyle(
                    color: Color(0xFF596579),
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class StockLossDialog extends StatefulWidget {
  const StockLossDialog({super.key, required this.products});
  final List<Product> products;

  @override
  State<StockLossDialog> createState() => _StockLossDialogState();
}

class _StockLossDialogState extends State<StockLossDialog> {
  final _formKey = GlobalKey<FormState>();
  final _quantityController = TextEditingController();
  final _noteController = TextEditingController();
  Product? _selectedProduct;
  String _cause = 'Casse';

  @override
  void initState() {
    super.initState();
    for (final product in widget.products) {
      if (product.quantity > 0) {
        _selectedProduct = product;
        break;
      }
    }
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate() || _selectedProduct == null) return;
    final product = _selectedProduct!;
    final loss = double.parse(
      _quantityController.text.trim().replaceAll(',', '.'),
    );
    final note = _noteController.text.trim();
    Navigator.pop(
      context,
      StocktakeRecord(
        product: product,
        previousQuantity: product.quantity,
        countedQuantity: product.quantity - loss,
        date: DateTime.now(),
        reason: 'Perte / rebut — $_cause${note.isEmpty ? '' : ' : $note'}',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final productsInStock = widget.products
        .where((p) => p.quantity > 0)
        .toList();
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      title: Row(
        children: [
          const Icon(Icons.delete_sweep_outlined, color: Color(0xFFB84A52)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _tr(
                'Enregistrer une perte ou un rebut',
                'Record a loss or write-off',
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: _dialogWidth(context, 480),
        child: productsInStock.isEmpty
            ? Text(
                _tr(
                  'Aucun produit avec une quantité disponible à ajuster.',
                  'There are no products with available quantity to adjust.',
                ),
              )
            : Form(
                key: _formKey,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _tr(
                          'La quantité déclarée sera retirée du stock et conservée dans l’historique.',
                          'The entered quantity will be removed from inventory and kept in the history.',
                        ),
                        style: const TextStyle(
                          color: Colors.black54,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<Product>(
                        value: _selectedProduct,
                        decoration: InputDecoration(
                          labelText: _tr('Produit', 'Product'),
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.inventory_2_outlined),
                        ),
                        items: productsInStock
                            .map(
                              (product) => DropdownMenuItem(
                                value: product,
                                child: Text(
                                  '${product.name} — ${_quantity(product.quantity)} ${product.unit}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (product) => setState(() {
                          _selectedProduct = product;
                          _quantityController.clear();
                        }),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _quantityController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: _tr('Quantité perdue', 'Quantity lost'),
                          helperText: _selectedProduct == null
                              ? null
                              : '${_tr('Disponible :', 'Available:')} ${_quantity(_selectedProduct!.quantity)} ${_selectedProduct!.unit}',
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.remove_circle_outline),
                        ),
                        validator: (value) {
                          final amount = double.tryParse(
                            (value ?? '').trim().replaceAll(',', '.'),
                          );
                          if (amount == null || amount <= 0)
                            return _tr(
                              'Saisis une quantité supérieure à zéro.',
                              'Enter a quantity greater than zero.',
                            );
                          if (_selectedProduct != null &&
                              amount > _selectedProduct!.quantity)
                            return _tr(
                              'La quantité dépasse le stock disponible.',
                              'The quantity exceeds available stock.',
                            );
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: _cause,
                        decoration: InputDecoration(
                          labelText: _tr('Motif', 'Reason'),
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(
                            Icons.assignment_late_outlined,
                          ),
                        ),
                        items: ['Casse', 'Péremption', 'Perte', 'Vol', 'Autre']
                            .map(
                              (cause) => DropdownMenuItem(
                                value: cause,
                                child: Text(cause),
                              ),
                            )
                            .toList(),
                        onChanged: (value) =>
                            setState(() => _cause = value ?? 'Autre'),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _noteController,
                        maxLines: 2,
                        decoration: InputDecoration(
                          labelText: _tr(
                            'Note (facultative)',
                            'Note (optional)',
                          ),
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.notes_outlined),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(_tr('Annuler', 'Cancel')),
        ),
        FilledButton.icon(
          onPressed: productsInStock.isEmpty ? null : _save,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFB84A52),
          ),
          icon: const Icon(Icons.check),
          label: Text(_tr('Enregistrer', 'Save')),
        ),
      ],
    );
  }
}

class StockContent extends StatefulWidget {
  const StockContent({
    super.key,
    required this.products,
    required this.isStaff,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
    required this.stocktakes,
    required this.onTakeStock,
    required this.onRecordLoss,
  });

  final List<Product> products;
  final bool isStaff;
  final VoidCallback onAdd;
  final ValueChanged<Product> onEdit;
  final Future<void> Function(Product) onDelete;
  final List<StocktakeRecord> stocktakes;
  final VoidCallback onTakeStock;
  final VoidCallback onRecordLoss;

  @override
  State<StockContent> createState() => _StockContentState();
}

class _StockContentState extends State<StockContent> {
  final _searchController = TextEditingController();
  bool _showLowStockOnly = false;
  String _selectedCategory = 'Toutes';
  int _visibleProductCount = 24;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _confirmDelete(BuildContext context, Product product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Supprimer ce produit ?'),
        content: Text(
          '« ' + product.name + ' » sera retiré de la liste du stock.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed == true) await widget.onDelete(product);
  }

  Future<void> _showProductDetails(Product product) async {
    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        final isOutOfStock = product.quantity <= 0;
        final isLow = product.quantity <= product.lowStockLimit;
        final expiryDays = _daysUntilExpiry(product);
        final stockValue = product.quantity * product.purchasePrice;
        final potentialMargin =
            product.quantity *
            (product.retailPrice * product.retailUnitsPerStockUnit -
                product.purchasePrice);
        return AlertDialog(
          title: Row(
            children: [
              Expanded(
                child: Text(
                  product.name,
                  style: const TextStyle(
                    color: navy,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (isLow)
                Chip(
                  backgroundColor: isOutOfStock
                      ? const Color(0xFFFDEBEC)
                      : const Color(0xFFFFF4E5),
                  label: Text(
                    isOutOfStock ? 'Rupture de stock' : 'À réapprovisionner',
                  ),
                ),
            ],
          ),
          content: SizedBox(
            width: _dialogWidth(context, 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  product.category,
                  style: const TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: const Color(0xFF202C82),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'QUANTITÉ DISPONIBLE',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${_quantity(product.quantity)} ${product.unit}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (isLow)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            'Seuil d’alerte : ${_quantity(product.lowStockLimit)} ${product.unit}',
                            style: const TextStyle(color: Color(0xFFFFD9D9)),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                if (!widget.isStaff)
                  _detailMetric('Valeur au coût d’achat', _money(stockValue)),
                _detailMetric(
                  'Prix de vente au détail',
                  '${_money(product.retailPrice)} / ${product.retailUnit}',
                ),
                if (!widget.isStaff)
                  _detailMetric(
                    'Marge potentielle estimée',
                    _money(potentialMargin),
                    color: teal,
                  ),
                if (product.expirationDate != null)
                  _detailMetric(
                    'Date de péremption',
                    _date(product.expirationDate!),
                    color: expiryDays! < 0
                        ? const Color(0xFFB84A52)
                        : expiryDays <= 30
                        ? const Color(0xFFD88931)
                        : ink,
                  ),
                const SizedBox(height: 8),
                const Text(
                  'Estimation indicative, avant frais généraux et pertes éventuelles.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Fermer'),
            ),
            if (!widget.isStaff)
              FilledButton.icon(
                onPressed: () => Navigator.pop(dialogContext, 'edit'),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Modifier'),
              ),
          ],
        );
      },
    );
    if (action == 'edit') widget.onEdit(product);
  }

  Widget _detailMetric(String label, String value, {Color color = ink}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Text(label, style: const TextStyle(color: Colors.black54)),
            ),
            Flexible(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: TextStyle(fontWeight: FontWeight.w700, color: color),
              ),
            ),
          ],
        ),
      );

  String? _productPhotoUrl(Product product) {
    final name = product.name.toLowerCase();
    if (name.contains('huile') || name.contains('oil')) {
      // Photo réelle d'huile de cuisine (Corn cheese, CC BY-SA 4.0).
      return 'https://commons.wikimedia.org/wiki/Special:FilePath/Cooking_oil.jpg?width=960';
    }
    if (name == 'ri' ||
        name.contains('riz') ||
        name.contains('rice') ||
        name.contains('arroz')) {
      // Sacs de riz photographiés en magasin (ProjectManhattan, CC BY-SA 3.0).
      return 'https://commons.wikimedia.org/wiki/Special:FilePath/Rice_sacks.jpg?width=960';
    }
    return null;
  }

  Widget _productPhotoFallback(Product product) {
    final name = product.name.toLowerCase();
    final icon = name.contains('huile') || name.contains('oil')
        ? Icons.water_drop_rounded
        : name.contains('riz') || name == 'ri' || name.contains('rice')
        ? Icons.grain
        : product.category.toLowerCase() == 'boissons'
        ? Icons.local_drink_rounded
        : product.category.toLowerCase() == 'alimentation'
        ? Icons.restaurant_rounded
        : Icons.inventory_2_rounded;
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFE5F4F1), Color(0xFFDDE5FF)],
        ),
      ),
      child: Center(
        child: Icon(icon, size: 58, color: navy.withValues(alpha: .72)),
      ),
    );
  }

  Widget _productPhoto(Product product) => Stack(
    fit: StackFit.expand,
    children: [
      _productPhotoFallback(product),
      if (product.photoPath case final photoPath?)
        _ProductImage(path: photoPath, fallback: _productPhotoFallback(product))
      else if (_productPhotoUrl(product) case final photoUrl?)
        Image.network(
          photoUrl,
          fit: BoxFit.cover,
          loadingBuilder: (context, child, progress) =>
              progress == null ? child : _productPhotoFallback(product),
          errorBuilder: (context, error, stack) =>
              _productPhotoFallback(product),
        ),
      Positioned(
        left: 12,
        bottom: 12,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: .58),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            _categoryLabel(product.category),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    ],
  );

  Widget _stockProductCard(Product product, double width) {
    final isOutOfStock = product.quantity <= 0;
    final isLow = product.quantity <= product.lowStockLimit;
    final expiryDays = _daysUntilExpiry(product);
    final margin =
        product.retailPrice -
        product.purchasePrice / product.retailUnitsPerStockUnit;
    if (width < 620) {
      return _mobileStockProductCard(
        product,
        width,
        isOutOfStock: isOutOfStock,
        isLow: isLow,
        expiryDays: expiryDays,
        margin: margin,
      );
    }
    return SizedBox(
      width: width,
      child: Card(
        clipBehavior: Clip.antiAlias,
        color: Colors.white,
        elevation: 8,
        shadowColor: const Color(0x30202C82),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: Color(0xFFDCE6EE)),
        ),
        child: InkWell(
          onTap: () => _showProductDetails(product),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 174,
                child: Stack(
                  children: [
                    Positioned.fill(child: _productPhoto(product)),
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: .02),
                              Colors.black.withValues(alpha: .38),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 10,
                      left: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: isOutOfStock
                              ? const Color(0xFFFDEBEC)
                              : isLow
                              ? const Color(0xFFFFF4E5)
                              : const Color(0xFFE9F3F2),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x33000000),
                              blurRadius: 10,
                              offset: Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Text(
                          isOutOfStock
                              ? _tr('Rupture de stock', 'Out of stock')
                              : isLow
                              ? _tr('À réapprovisionner', 'Low stock')
                              : _tr('En stock', 'In stock'),
                          style: TextStyle(
                            color: isOutOfStock
                                ? const Color(0xFFB84A52)
                                : isLow
                                ? const Color(0xFFD88931)
                                : const Color(0xFF32766F),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    if (!widget.isStaff)
                      Positioned(
                        top: 4,
                        right: 4,
                        child: Material(
                          color: Colors.white.withValues(alpha: .96),
                          shape: const CircleBorder(),
                          elevation: 4,
                          child: PopupMenuButton<String>(
                            tooltip: _tr(
                              'Actions sur le produit',
                              'Product actions',
                            ),
                            icon: const Icon(
                              Icons.more_vert_rounded,
                              color: ink,
                            ),
                            onSelected: (action) {
                              if (action == 'edit') widget.onEdit(product);
                              if (action == 'delete')
                                _confirmDelete(context, product);
                            },
                            itemBuilder: (_) => [
                              PopupMenuItem(
                                value: 'edit',
                                child: ListTile(
                                  leading: Icon(Icons.edit_outlined),
                                  title: Text(
                                    _tr('Modifier le produit', 'Edit product'),
                                  ),
                                ),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: ListTile(
                                  leading: Icon(
                                    Icons.delete_outline,
                                    color: Color(0xFFB84A52),
                                  ),
                                  title: Text(_tr('Supprimer', 'Delete')),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (product.photoCredit != null &&
                        product.photoPageUrl != null)
                      Positioned(
                        right: 8,
                        bottom: 8,
                        child: Material(
                          color: Colors.white.withValues(alpha: .96),
                          shape: const CircleBorder(),
                          elevation: 3,
                          child: IconButton(
                            tooltip: _tr(
                              'Informations sur la photo',
                              'Photo information',
                            ),
                            visualDensity: VisualDensity.compact,
                            onPressed: () =>
                                _openPhotoCredit(product.photoPageUrl),
                            icon: const Icon(
                              Icons.info_outline_rounded,
                              size: 19,
                              color: navy,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.white, Color(0xFFF7FBFD)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(15, 14, 15, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: ink,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F5F4),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.inventory_2_rounded,
                              size: 15,
                              color: teal,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '${_quantity(product.quantity)} ${_unitLabel(product.unit)} ${_tr('disponibles', 'available')}',
                              style: const TextStyle(
                                color: Color(0xFF087F82),
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (expiryDays != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          expiryDays < 0
                              ? '${_tr('Périmé depuis ', 'Expired since ')}${_date(product.expirationDate!)}'
                              : expiryDays == 0
                              ? _tr('Péremption aujourd’hui', 'Expires today')
                              : '${_tr('Péremption : ', 'Expiry: ')}${_date(product.expirationDate!)}${expiryDays <= 30 ? ' • ${_tr('dans ', 'in ')}$expiryDays ${_tr('j', 'd')}' : ''}',
                          style: TextStyle(
                            color: expiryDays < 0
                                ? const Color(0xFFB84A52)
                                : expiryDays <= 30
                                ? const Color(0xFFD88931)
                                : Colors.black54,
                            fontWeight: expiryDays <= 30
                                ? FontWeight.w700
                                : FontWeight.normal,
                            fontSize: 12,
                          ),
                        ),
                      ],
                      if (product.barcode.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          '${_tr('Code : ', 'Barcode: ')}${product.barcode}',
                          style: const TextStyle(
                            color: Colors.black45,
                            fontSize: 11,
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          if (!widget.isStaff) ...[
                            Expanded(
                              child: _cardPrice(
                                _tr('Achat', 'Cost'),
                                '${_money(product.purchasePrice)} / ${_unitLabel(product.unit)}',
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Expanded(
                            child: _cardPrice(
                              _tr('Détail', 'Retail'),
                              '${_money(product.retailPrice)} / ${_unitLabel(product.retailUnit)}',
                            ),
                          ),
                        ],
                      ),
                      if (!widget.isStaff && product.marketPrice != null) ...[
                        const SizedBox(height: 7),
                        Text(
                          '${_tr('Marché : ', 'Market: ')}${_money(product.marketPrice!)} / ${_unitLabel(product.retailUnit)}',
                          style: const TextStyle(
                            color: Colors.black54,
                            fontSize: 11,
                          ),
                        ),
                      ],
                      if (!widget.isStaff) ...[
                        const SizedBox(height: 9),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: margin >= 0
                                  ? const [Color(0xFFE4F7F0), Color(0xFFD3F0E8)]
                                  : const [
                                      Color(0xFFFFEEEE),
                                      Color(0xFFFFE2E3),
                                    ],
                            ),
                            borderRadius: BorderRadius.circular(13),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x12000000),
                                blurRadius: 7,
                                offset: Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Text(
                            '${_tr('Marge indicative : ', 'Estimated margin: ')}${_money(margin)} / ${_unitLabel(product.retailUnit)}',
                            style: TextStyle(
                              color: margin >= 0
                                  ? const Color(0xFF32766F)
                                  : const Color(0xFFB84A52),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _mobileStockProductCard(
    Product product,
    double width, {
    required bool isOutOfStock,
    required bool isLow,
    required int? expiryDays,
    required double margin,
  }) {
    final statusColor = isOutOfStock
        ? const Color(0xFFB84A52)
        : isLow
        ? const Color(0xFFB87525)
        : const Color(0xFF32766F);
    final statusBackground = isOutOfStock
        ? const Color(0xFFFDEBEC)
        : isLow
        ? const Color(0xFFFFF4E5)
        : const Color(0xFFE9F3F2);
    return SizedBox(
      width: width,
      child: Card(
        margin: EdgeInsets.zero,
        color: Colors.white,
        elevation: 3,
        shadowColor: const Color(0x221B2C73),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFFE2E8EF)),
        ),
        child: InkWell(
          onTap: () => _showProductDetails(product),
          child: Padding(
            padding: const EdgeInsets.all(11),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(15),
                  child: SizedBox(
                    width: 104,
                    height: 116,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _productPhoto(product),
                        Align(
                          alignment: Alignment.bottomCenter,
                          child: Container(
                            height: 35,
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Colors.transparent, Color(0x88000000)],
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 6,
                          right: 6,
                          bottom: 6,
                          child: Text(
                            _categoryLabel(product.category),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              product.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: navy,
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          if (!widget.isStaff)
                            SizedBox(
                              width: 32,
                              height: 30,
                              child: PopupMenuButton<String>(
                                padding: EdgeInsets.zero,
                                tooltip: _tr(
                                  'Actions produit',
                                  'Product actions',
                                ),
                                icon: const Icon(
                                  Icons.more_horiz_rounded,
                                  color: ink,
                                ),
                                onSelected: (action) {
                                  if (action == 'edit') widget.onEdit(product);
                                  if (action == 'delete')
                                    _confirmDelete(context, product);
                                },
                                itemBuilder: (_) => [
                                  PopupMenuItem(
                                    value: 'edit',
                                    child: Text(_tr('Modifier', 'Edit')),
                                  ),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Text(_tr('Supprimer', 'Delete')),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '${_quantity(product.quantity)} ${_unitLabel(product.unit)} ${_tr('disponibles', 'available')}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF5F6877),
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        '${_money(product.retailPrice)} / ${_unitLabel(product.retailUnit)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF137F83),
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Wrap(
                        spacing: 5,
                        runSpacing: 5,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: statusBackground,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isOutOfStock
                                      ? Icons.remove_circle_outline
                                      : isLow
                                      ? Icons.warning_amber_rounded
                                      : Icons.check_circle_outline,
                                  size: 13,
                                  color: statusColor,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  isOutOfStock
                                      ? _tr('Rupture', 'Out')
                                      : isLow
                                      ? _tr('Stock bas', 'Low')
                                      : _tr('En stock', 'In stock'),
                                  style: TextStyle(
                                    color: statusColor,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (!widget.isStaff)
                            Text(
                              '${_tr('Marge', 'Margin')} : ${_money(margin)}',
                              style: TextStyle(
                                color: margin >= 0
                                    ? const Color(0xFF56746F)
                                    : const Color(0xFFB84A52),
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                        ],
                      ),
                      if (expiryDays != null && expiryDays <= 30) ...[
                        const SizedBox(height: 5),
                        Text(
                          expiryDays < 0
                              ? _tr('Périmé', 'Expired')
                              : expiryDays == 0
                              ? _tr('Expire aujourd’hui', 'Expires today')
                              : '${_tr('Expire dans', 'Expires in')} $expiryDays ${_tr('j', 'd')}',
                          style: const TextStyle(
                            color: Color(0xFFB87525),
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (product.photoCredit != null && product.photoPageUrl != null)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: _tr('Informations photo', 'Photo details'),
                    onPressed: () => _openPhotoCredit(product.photoPageUrl),
                    icon: const Icon(
                      Icons.info_outline_rounded,
                      color: navy,
                      size: 19,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _cardPrice(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(fontSize: 11, color: Colors.black45)),
      const SizedBox(height: 2),
      Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: ink,
        ),
      ),
    ],
  );

  Future<void> _openPhotoCredit(String? url) async {
    if (url == null || url.isEmpty) return;
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final products = widget.products;
    final lowStockProducts = products
        .where((product) => product.quantity <= product.lowStockLimit)
        .toList();
    final expiringProducts = products.where((product) {
      final days = _daysUntilExpiry(product);
      return days != null && days <= 30;
    }).toList();
    final stockValue = products.fold(
      0.0,
      (sum, product) => sum + product.quantity * product.purchasePrice,
    );
    final search = _normalizeStockSearch(_searchController.text);
    final categories =
        products.map((product) => product.category).toSet().toList()..sort();
    final sortedProducts =
        List<Product>.from(
          products.where((product) {
            final matchesSearch = _matchesStockSearch(product, search);
            final matchesStock =
                !_showLowStockOnly || product.quantity <= product.lowStockLimit;
            final matchesCategory =
                _selectedCategory == 'Toutes' ||
                product.category == _selectedCategory;
            return matchesSearch && matchesStock && matchesCategory;
          }),
        )..sort((a, b) {
          final aLow = a.quantity <= a.lowStockLimit;
          final bLow = b.quantity <= b.lowStockLimit;
          if (aLow != bLow) return aLow ? -1 : 1;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
    return ListView(
      padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 600 ? 16 : 26),
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final actions = Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (widget.isStaff)
                  Chip(
                    avatar: Icon(Icons.visibility_outlined, size: 18),
                    label: Text(_tr('Consultation seule', 'View only')),
                  ),
                if (!widget.isStaff && products.isNotEmpty)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: navy,
                      backgroundColor: Colors.white,
                      side: const BorderSide(color: Color(0xFFBAC7EF)),
                      elevation: 2,
                      shadowColor: const Color(0x221B2C73),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 13,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                    onPressed: widget.onTakeStock,
                    icon: const Icon(Icons.fact_check_outlined),
                    label: Text(_tr('Faire un inventaire', 'Take inventory')),
                  ),
                if (!widget.isStaff &&
                    products.any((product) => product.quantity > 0))
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFB84A52),
                      backgroundColor: Colors.white,
                      side: const BorderSide(color: Color(0xFFE9C8CB)),
                      elevation: 2,
                      shadowColor: const Color(0x1AB84A52),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 13,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                    onPressed: widget.onRecordLoss,
                    icon: const Icon(Icons.delete_sweep_outlined),
                    label: Text(_tr('Pertes & rebuts', 'Losses & write-offs')),
                  ),
                if (!widget.isStaff)
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: teal,
                      foregroundColor: Colors.white,
                      elevation: 5,
                      shadowColor: teal.withValues(alpha: .35),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 13,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                    onPressed: widget.onAdd,
                    icon: const Icon(Icons.add),
                    label: Text(_tr('Ajouter un produit', 'Add a product')),
                  ),
              ],
            );
            return _BizPageHero(
              title: _tr('Stock', 'Inventory'),
              subtitle: _tr(
                'Vérifie les quantités, les alertes et la valeur de ton stock.',
                'Review quantities, alerts, and inventory value.',
              ),
              icon: Icons.inventory_2_rounded,
              action: actions,
            );
          },
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: 250,
              child: SummaryCard(
                title: _tr('Produits référencés', 'Products listed'),
                value: products.length.toString(),
                icon: Icons.inventory_2_outlined,
                color: teal,
              ),
            ),
            SizedBox(
              width: 250,
              child: SummaryCard(
                title: _tr('À réapprovisionner', 'Low stock'),
                value: lowStockProducts.length.toString(),
                icon: Icons.warning_amber_outlined,
                color: lowStockProducts.isEmpty
                    ? teal
                    : const Color(0xFFB84A52),
              ),
            ),
            if (!widget.isStaff)
              SizedBox(
                width: 250,
                child: SummaryCard(
                  title: _tr(
                    'Valeur du stock au coût d’achat',
                    'Inventory value at cost',
                  ),
                  value: _money(stockValue),
                  icon: Icons.account_balance_wallet_outlined,
                  color: const Color(0xFF527ACB),
                ),
              ),
            SizedBox(
              width: 250,
              child: SummaryCard(
                title: _tr(
                  'Dates à vérifier (30 j)',
                  'Expiry dates to check (30 d)',
                ),
                value: expiringProducts.length.toString(),
                icon: Icons.event_busy_outlined,
                color: expiringProducts.isEmpty
                    ? teal
                    : const Color(0xFFD88931),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (lowStockProducts.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF0F0),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFF4D4D7)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: Color(0xFFB84A52),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${lowStockProducts.length} ${_tr('produit(s) sous le seuil : ', 'product(s) below the threshold: ')}${lowStockProducts.take(3).map((product) => product.name).join(' • ')}${lowStockProducts.length > 3 ? '…' : ''}',
                    style: const TextStyle(
                      color: Color(0xFF8E3038),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (expiringProducts.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF6E8),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFF5DFB8)),
            ),
            child: Row(
              children: [
                const Icon(Icons.event_busy_outlined, color: Color(0xFFD88931)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${_tr('À vérifier : ', 'Check: ')}${expiringProducts.take(4).map((product) {
                      final days = _daysUntilExpiry(product)!;
                      return days < 0
                          ? '${product.name} (${_tr('périmé', 'expired')})'
                          : days == 0
                          ? '${product.name} (${_tr('aujourd’hui', 'today')})'
                          : '${product.name} (${_tr('dans ', 'in ')}$days ${_tr('j', 'd')})';
                    }).join(' • ')}${expiringProducts.length > 4 ? '…' : ''}',
                    style: const TextStyle(
                      color: Color(0xFF875A18),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (products.isEmpty)
          Card(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                children: [
                  const Icon(Icons.inventory_2_outlined, size: 42, color: teal),
                  const SizedBox(height: 12),
                  Text(
                    _tr(
                      'Votre stock est vide pour le moment.',
                      'Your inventory is empty.',
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: widget.onAdd,
                    icon: const Icon(Icons.add),
                    label: Text(
                      _tr(
                        'Ajouter mon premier produit',
                        'Add my first product',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
        else ...[
          const SizedBox(height: 4),
          TextField(
            controller: _searchController,
            onChanged: (_) => setState(() => _visibleProductCount = 24),
            decoration: InputDecoration(
              hintText: _tr(
                'Rechercher un produit ou une catégorie',
                'Search products or categories',
              ),
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: _tr('Effacer la recherche', 'Clear search'),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {});
                      },
                      icon: const Icon(Icons.close),
                    ),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFFDDE2EC)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFFDDE2EC)),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: Text(_tr('Tous', 'All')),
                selected: !_showLowStockOnly,
                selectedColor: const Color(0xFF23318E),
                labelStyle: TextStyle(
                  color: !_showLowStockOnly ? Colors.white : ink,
                  fontWeight: FontWeight.w700,
                ),
                onSelected: (_) => setState(() {
                  _showLowStockOnly = false;
                  _visibleProductCount = 24;
                }),
              ),
              ChoiceChip(
                label: Text(
                  '${_tr('À réapprovisionner', 'Low stock')} (${lowStockProducts.length})',
                ),
                selected: _showLowStockOnly,
                selectedColor: const Color(0xFFDE6E55),
                labelStyle: TextStyle(
                  color: _showLowStockOnly ? Colors.white : ink,
                  fontWeight: FontWeight.w700,
                ),
                onSelected: (_) => setState(() {
                  _showLowStockOnly = true;
                  _visibleProductCount = 24;
                }),
              ),
            ],
          ),
          if (categories.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: Text(_tr('Toutes catégories', 'All categories')),
                  selected: _selectedCategory == 'Toutes',
                  selectedColor: teal,
                  labelStyle: TextStyle(
                    color: _selectedCategory == 'Toutes' ? Colors.white : ink,
                    fontWeight: FontWeight.w700,
                  ),
                  onSelected: (_) => setState(() {
                    _selectedCategory = 'Toutes';
                    _visibleProductCount = 24;
                  }),
                ),
                ...categories.map(
                  (category) => ChoiceChip(
                    label: Text(_categoryLabel(category)),
                    selected: _selectedCategory == category,
                    selectedColor: teal,
                    labelStyle: TextStyle(
                      color: _selectedCategory == category ? Colors.white : ink,
                      fontWeight: FontWeight.w700,
                    ),
                    onSelected: (_) => setState(() {
                      _selectedCategory = category;
                      _visibleProductCount = 24;
                    }),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          if (sortedProducts.isEmpty)
            Card(
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const Icon(
                      Icons.search_off_outlined,
                      color: teal,
                      size: 36,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _showLowStockOnly
                          ? _tr(
                              'Aucun produit sous le seuil de stock.',
                              'No products are below the stock threshold.',
                            )
                          : _tr(
                              'Aucun produit ne correspond à cette recherche.',
                              'No products match this search.',
                            ),
                    ),
                    if (_showLowStockOnly)
                      TextButton(
                        onPressed: () =>
                            setState(() => _showLowStockOnly = false),
                        child: Text(
                          _tr(
                            'Afficher tous les produits',
                            'Show all products',
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 1400
                    ? 4
                    : constraints.maxWidth >= 1000
                    ? 3
                    : constraints.maxWidth >= 620
                    ? 2
                    : 1;
                const gap = 14.0;
                final cardWidth =
                    (constraints.maxWidth - (columns - 1) * gap) / columns;
                return Column(
                  children: [
                    Wrap(
                      spacing: gap,
                      runSpacing: gap,
                      children: sortedProducts
                          .take(_visibleProductCount)
                          .map(
                            (product) => _stockProductCard(product, cardWidth),
                          )
                          .toList(),
                    ),
                    if (sortedProducts.length > _visibleProductCount)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: OutlinedButton.icon(
                          onPressed: () =>
                              setState(() => _visibleProductCount += 24),
                          icon: const Icon(Icons.expand_more_rounded),
                          label: Text(
                            'Afficher ${sortedProducts.length - _visibleProductCount > 24 ? '24 autres' : 'les ${sortedProducts.length - _visibleProductCount} derniers'} produits',
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
        ],
        const SizedBox(height: 10),
        Text(
          _tr(
            'La marge affichée est indicative et ne comprend pas les frais du trajet.',
            'The displayed margin is an estimate and excludes delivery expenses.',
          ),
          style: TextStyle(fontSize: 12, color: Colors.black45),
        ),
        if (widget.stocktakes.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text(
            _tr('Derniers écarts d’inventaire', 'Recent inventory adjustments'),
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.bold,
              color: ink,
            ),
          ),
          const SizedBox(height: 8),
          ...widget.stocktakes
              .take(10)
              .map(
                (item) => Card(
                  color: Colors.white,
                  child: ListTile(
                    leading: Icon(
                      item.difference < 0
                          ? Icons.trending_down
                          : Icons.trending_up,
                      color: item.difference < 0
                          ? const Color(0xFFB84A52)
                          : teal,
                    ),
                    title: Text(
                      item.product.name +
                          ' • ' +
                          (item.difference > 0 ? '+' : '') +
                          _quantity(item.difference) +
                          ' ' +
                          item.product.unit,
                    ),
                    subtitle: Text(
                      _date(item.date) +
                          ' • ${_tr('Avant : ', 'Before: ')}' +
                          _quantity(item.previousQuantity) +
                          ' • ${_tr('Compté : ', 'Counted: ')}' +
                          _quantity(item.countedQuantity) +
                          (item.reason.isEmpty ? '' : '\n' + item.reason),
                    ),
                  ),
                ),
              ),
        ],
      ],
    );
  }
}

String _normalizeStockSearch(String value) => value
    .toLowerCase()
    .replaceAll('œ', 'oe')
    .replaceAll('æ', 'ae')
    .replaceAll(RegExp(r'[àáâäãå]'), 'a')
    .replaceAll(RegExp(r'[èéêë]'), 'e')
    .replaceAll(RegExp(r'[ìíîï]'), 'i')
    .replaceAll(RegExp(r'[òóôöõ]'), 'o')
    .replaceAll(RegExp(r'[ùúûü]'), 'u')
    .replaceAll('ç', 'c')
    .replaceAll(RegExp(r'[̀-ͯ]'), '')
    .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
    .trim();

bool _matchesStockSearch(Product product, String query) {
  if (query.isEmpty) return true;
  final fields = [
    product.name,
    _categoryLabel(product.category),
    product.barcode,
  ].map(_normalizeStockSearch).where((value) => value.isNotEmpty).toList();
  final tokens = fields.expand((value) => value.split(' ')).toList();
  return query
      .split(' ')
      .every(
        (part) =>
            fields.any((field) => field.contains(part)) ||
            tokens.any(
              (token) =>
                  _stockEditDistanceAtMost(
                    token,
                    part,
                    part.length <= 4 ? 1 : 2,
                  ) <=
                  (part.length <= 4 ? 1 : 2),
            ),
      );
}

int _stockEditDistanceAtMost(String a, String b, int limit) {
  if ((a.length - b.length).abs() > limit) return limit + 1;
  var previous = List<int>.generate(b.length + 1, (index) => index);
  for (var i = 1; i <= a.length; i++) {
    final current = List<int>.filled(b.length + 1, limit + 1);
    current[0] = i;
    for (var j = 1; j <= b.length; j++) {
      current[j] = [
        current[j - 1] + 1,
        previous[j] + 1,
        previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1),
      ].reduce((x, y) => x < y ? x : y);
    }
    previous = current;
  }
  return previous[b.length];
}

class EditProductDialog extends StatefulWidget {
  const EditProductDialog({
    super.key,
    required this.product,
    required this.businessId,
    this.existingNames = const {},
    this.existingBarcodes = const {},
  });
  final Product product;
  final String businessId;
  final Set<String> existingNames;
  final Set<String> existingBarcodes;
  @override
  State<EditProductDialog> createState() => _EditProductDialogState();
}

class _EditProductDialogState extends State<EditProductDialog> {
  final formKey = GlobalKey<FormState>();
  late DateTime? expirationDate = widget.product.expirationDate;
  late String? photoPath = widget.product.photoPath;
  late String? photoCredit = widget.product.photoCredit;
  late String? photoPageUrl = widget.product.photoPageUrl;
  late String? photoPhotographerUrl = widget.product.photoPhotographerUrl;
  late final name = TextEditingController(text: widget.product.name);
  late final barcode = TextEditingController(text: widget.product.barcode);
  late String retailUnit = widget.product.retailUnit;
  late final customRetailUnit = TextEditingController(
    text: widget.product.retailUnit,
  );
  late bool customRetailUnitSelected =
      !_commonProductUnits.contains(widget.product.retailUnit) &&
      widget.product.retailUnit != widget.product.unit;
  late final wholesale = TextEditingController(
    text: widget.product.wholesalePrice.toStringAsFixed(0),
  );
  late final retail = TextEditingController(
    text: widget.product.retailPrice.toStringAsFixed(0),
  );
  late final market = TextEditingController(
    text: widget.product.marketPrice?.toStringAsFixed(0) ?? '',
  );
  late final lowStock = TextEditingController(
    text: _quantity(widget.product.lowStockLimit),
  );
  late final conversion = TextEditingController(
    text: _quantity(_knownConversion ?? widget.product.retailUnitsPerStockUnit),
  );
  String get _saleUnit =>
      customRetailUnitSelected ? customRetailUnit.text.trim() : retailUnit;
  double? get _knownConversion =>
      widget.product.unit == 'Soghor' && _saleUnit == 'Kg'
      ? 3
      : widget.product.unit == 'Kg' && _saleUnit == 'Soghor'
      ? 1 / 3
      : null;
  double get _unitsPerStockUnit => _saleUnit == widget.product.unit
      ? 1
      : _knownConversion ??
            double.tryParse(conversion.text.trim().replaceAll(',', '.')) ??
            0;
  double get _retailMargin =>
      (double.tryParse(retail.text.trim().replaceAll(',', '.')) ?? 0) -
      (_unitsPerStockUnit <= 0
          ? 0
          : widget.product.purchasePrice / _unitsPerStockUnit);
  double get _minimumRetailPrice => _unitsPerStockUnit <= 0
      ? 0
      : (widget.product.purchasePrice / _unitsPerStockUnit).ceilToDouble();
  @override
  void dispose() {
    name.dispose();
    wholesale.dispose();
    retail.dispose();
    market.dispose();
    lowStock.dispose();
    conversion.dispose();
    barcode.dispose();
    customRetailUnit.dispose();
    super.dispose();
  }

  String? _positive(String? value, {bool allowZero = false}) {
    final number = double.tryParse((value ?? '').trim().replaceAll(',', '.'));
    if (number == null || number < 0 || (!allowZero && number == 0))
      return allowZero
          ? 'Saisis un nombre valide.'
          : 'Saisis un montant supérieur à zéro.';
    return null;
  }

  void _save() {
    if (!formKey.currentState!.validate()) return;
    final marketText = market.text.trim();
    Navigator.pop(
      context,
      widget.product.copyWith(
        name: name.text.trim(),
        wholesalePrice: double.parse(
          wholesale.text.trim().replaceAll(',', '.'),
        ),
        retailPrice: double.parse(retail.text.trim().replaceAll(',', '.')),
        retailUnit: _saleUnit,
        retailUnitsPerStockUnit: _unitsPerStockUnit,
        marketPrice: marketText.isEmpty
            ? null
            : double.parse(marketText.replaceAll(',', '.')),
        clearMarketPrice: marketText.isEmpty,
        lowStockLimit: double.parse(lowStock.text.trim().replaceAll(',', '.')),
        barcode: barcode.text.trim(),
        expirationDate: expirationDate,
        clearExpirationDate: expirationDate == null,
        photoPath: photoPath,
        clearPhotoPath: photoPath == null,
        photoCredit: photoCredit,
        photoPageUrl: photoPageUrl,
        photoPhotographerUrl: photoPhotographerUrl,
        clearPhotoMetadata: photoPath == null || photoCredit == null,
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    bool allowZero = false,
    bool optional = false,
  }) => TextFormField(
    controller: controller,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    onChanged: (_) => setState(() {}),
    validator: (v) => optional && (v == null || v.trim().isEmpty)
        ? null
        : _positive(v, allowZero: allowZero),
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
    ),
  );
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Modifier • ' + widget.product.name),
    content: SizedBox(
      width: _dialogWidth(context, 460),
      child: Form(
        key: formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: name,
                textCapitalization: TextCapitalization.sentences,
                validator: (value) {
                  final normalized = (value ?? '').trim().toLowerCase();
                  if (normalized.isEmpty) {
                    return 'Le nom du produit est obligatoire.';
                  }
                  if (widget.existingNames.contains(normalized)) {
                    return 'Un produit de cette catégorie porte déjà ce nom.';
                  }
                  return null;
                },
                decoration: const InputDecoration(
                  labelText: 'Nom du produit',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              _field(
                wholesale,
                'Prix de vente en gros / ${widget.product.unit} ($_currencyLabel)',
              ),
              const SizedBox(height: 12),
              _barcodeField(context, barcode, widget.existingBarcodes),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: customRetailUnitSelected
                    ? _customProductUnitValue
                    : retailUnit,
                decoration: const InputDecoration(
                  labelText: 'Unité de vente au détail',
                  border: OutlineInputBorder(),
                ),
                items: _productUnitItems(extraUnits: [widget.product.unit]),
                onChanged: (value) => setState(() {
                  final oldRatio = _unitsPerStockUnit;
                  final oldMarket = double.tryParse(
                    market.text.trim().replaceAll(',', '.'),
                  );
                  final wasCustomUnit = customRetailUnitSelected;
                  customRetailUnitSelected = value == _customProductUnitValue;
                  if (customRetailUnitSelected && !wasCustomUnit) {
                    customRetailUnit.clear();
                  }
                  if (!customRetailUnitSelected && value != null) {
                    retailUnit = value;
                  }
                  if (_saleUnit == widget.product.unit) {
                    conversion.text = '1';
                  } else if (_knownConversion != null) {
                    conversion.text = _knownConversion.toString();
                  } else if (widget.product.unit == 'Bidon' &&
                      _saleUnit == 'Litre' &&
                      oldRatio <= 1) {
                    conversion.text = '25';
                  } else if (oldRatio <= 1) {
                    conversion.text = '1';
                  }
                  final newRatio = _unitsPerStockUnit;
                  if (oldMarket != null && newRatio > 0) {
                    market.text = (oldMarket * oldRatio / newRatio)
                        .toStringAsFixed(0);
                  }
                }),
              ),
              if (customRetailUnitSelected) ...[
                const SizedBox(height: 10),
                TextFormField(
                  controller: customRetailUnit,
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) => setState(() {}),
                  validator: (value) =>
                      customRetailUnitSelected &&
                          (value == null || value.trim().isEmpty)
                      ? 'Saisis le nom de l’unité de vente.'
                      : null,
                  decoration: const InputDecoration(
                    labelText: 'Nom de l’unité de vente',
                    hintText: 'Ex. : Verre',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              _field(
                retail,
                'Prix de vente au détail / $_saleUnit ($_currencyLabel)',
              ),
              if (_saleUnit != widget.product.unit) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: conversion,
                  readOnly: _knownConversion != null,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (_) => setState(() {}),
                  validator: (value) {
                    if (_saleUnit == widget.product.unit) return null;
                    final number = double.tryParse(
                      (value ?? '').trim().replaceAll(',', '.'),
                    );
                    return number == null || number <= 0
                        ? 'Saisis le nombre d’unités dans un ${widget.product.unit.toLowerCase()}.'
                        : null;
                  },
                  decoration: InputDecoration(
                    labelText:
                        'Quantité de ${_saleUnit.toLowerCase()} dans 1 ${widget.product.unit.toLowerCase()}',
                    hintText:
                        widget.product.unit == 'Bidon' && retailUnit == 'Litre'
                        ? 'Ex. : 25 si le bidon contient 25 litres'
                        : 'Ex. : 50 si 1 sac contient 50 kg',
                    border: const OutlineInputBorder(),
                  ),
                ),
                if (_knownConversion != null)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Conversion fixe : 1 Soghor = 3 kg. Le stock et les ventes utilisent cette équivalence.',
                        style: TextStyle(color: Colors.black54, fontSize: 12),
                      ),
                    ),
                  ),
                if (widget.product.unit == 'Bidon' && _saleUnit == 'Litre')
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Suggestion pour un bidon d’huile : 25 litres. Vérifie la capacité inscrite sur le bidon.',
                        style: TextStyle(color: Colors.black54, fontSize: 12),
                      ),
                    ),
                  ),
              ],
              const SizedBox(height: 12),
              _field(
                market,
                'Prix actuel du marché (facultatif)',
                optional: true,
              ),
              const SizedBox(height: 12),
              _field(
                lowStock,
                'Alerte de stock bas à partir de',
                allowZero: true,
              ),
              const SizedBox(height: 12),
              _expirationDatePicker(
                context,
                expirationDate,
                (value) => setState(() => expirationDate = value),
              ),
              const SizedBox(height: 16),
              ProductPhotoSelector(
                businessId: widget.businessId,
                productName: widget.product.name,
                photoPath: photoPath,
                photoCredit: photoCredit,
                photoPageUrl: photoPageUrl,
                photoPhotographerUrl: photoPhotographerUrl,
                onChanged: (value) => setState(() {
                  photoPath = value?.path;
                  photoCredit = value?.credit;
                  photoPageUrl = value?.pageUrl;
                  photoPhotographerUrl = null;
                }),
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _retailMargin >= 0
                      ? const Color(0xFFEAF7F0)
                      : const Color(0xFFFFF0F0),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Prix minimum pour couvrir l’achat : ${_money(_minimumRetailPrice)} / $_saleUnit (soit ${_money(widget.product.purchasePrice)} par ${widget.product.unit})',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _retailMargin < 0
                          ? 'Attention : le prix de détail actuel ferait vendre à perte, avant autres frais.'
                          : 'Marge indicative : ${_money(_retailMargin)} par $_saleUnit • ${_money(_retailMargin * widget.product.quantity * _unitsPerStockUnit)} pour le stock actuel',
                      style: TextStyle(
                        color: _retailMargin >= 0
                            ? const Color(0xFF278052)
                            : const Color(0xFFB84A52),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _saleUnit == widget.product.retailUnit
                    ? 'Corriger la conversion recalculera le stock et les ventes déjà enregistrées avec cette unité.'
                    : 'Les anciennes ventes garderont leur unité d’origine. Cette unité servira pour les prochaines ventes.',
                style: const TextStyle(color: Colors.black54),
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Annuler'),
      ),
      FilledButton(
        onPressed: _save,
        child: const Text('Enregistrer les modifications'),
      ),
    ],
  );
}

class ProductPhotoSelection {
  const ProductPhotoSelection({required this.path, this.credit, this.pageUrl});
  final String path;
  final String? credit;
  final String? pageUrl;
}

Widget _barcodeField(
  BuildContext context,
  TextEditingController controller,
  Set<String> existingBarcodes, {
  ValueChanged<String>? onChanged,
}) => Row(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Expanded(
      child: TextFormField(
        controller: controller,
        keyboardType: TextInputType.number,
        onChanged: onChanged,
        decoration: const InputDecoration(
          labelText: 'Code-barres (facultatif)',
          prefixIcon: Icon(Icons.qr_code_2),
          border: OutlineInputBorder(),
        ),
        validator: (value) {
          final code = (value ?? '').trim();
          if (code.isNotEmpty && existingBarcodes.contains(code.toLowerCase()))
            return 'Ce code-barres est déjà attribué à un autre produit.';
          return null;
        },
      ),
    ),
    const SizedBox(width: 8),
    IconButton.filledTonal(
      tooltip: 'Scanner le code-barres',
      onPressed: () async {
        final code = await showBarcodeScanner(context);
        if (code != null) {
          controller.text = code;
          onChanged?.call(code);
        }
      },
      icon: const Icon(Icons.camera_alt_outlined),
    ),
  ],
);

Future<String?> showBarcodeScanner(
  BuildContext parentContext,
) => showDialog<String>(
  context: parentContext,
  builder: (context) => AlertDialog(
    title: const Text('Scanner un code-barres'),
    content: SizedBox(
      width: _dialogWidth(context, 420),
      height: _dialogHeight(context, 320),
      child: Column(
        children: [
          const Text(
            'Place le code dans le cadre. La lecture se fait automatiquement.',
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: MobileScanner(
                onDetect: (capture) {
                  for (final barcode in capture.barcodes) {
                    final value = barcode.rawValue?.trim();
                    if (value != null && value.isNotEmpty) {
                      Navigator.of(context).pop(value);
                      return;
                    }
                  }
                },
              ),
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Annuler'),
      ),
    ],
  ),
);

class OnlineProductPhoto {
  const OnlineProductPhoto({
    required this.imageUrl,
    required this.credit,
    required this.pageUrl,
    this.alt = '',
  });
  final String imageUrl;
  final String credit;
  final String pageUrl;
  final String alt;

  factory OnlineProductPhoto.fromJson(Map<String, dynamic> json) =>
      OnlineProductPhoto(
        imageUrl: json['imageUrl'] as String? ?? '',
        credit: json['credit'] as String? ?? 'Auteur ou licence non indiqués',
        pageUrl: json['pageUrl'] as String? ?? 'https://commons.wikimedia.org',
        alt: json['alt'] as String? ?? '',
      );
}

class ProductPhotoSelector extends StatefulWidget {
  const ProductPhotoSelector({
    super.key,
    required this.businessId,
    required this.productName,
    required this.photoPath,
    this.photoCredit,
    this.photoPageUrl,
    this.photoPhotographerUrl,
    required this.onChanged,
  });
  final String businessId;
  final String productName;
  final String? photoPath;
  final String? photoCredit;
  final String? photoPageUrl;
  final String? photoPhotographerUrl;
  final ValueChanged<ProductPhotoSelection?> onChanged;

  @override
  State<ProductPhotoSelector> createState() => _ProductPhotoSelectorState();
}

class _ProductPhotoSelectorState extends State<ProductPhotoSelector> {
  bool _uploading = false;

  Future<void> _searchOnline() async {
    final selected = await showDialog<OnlineProductPhoto>(
      context: context,
      builder: (_) => OnlineImageSearchDialog(initialQuery: widget.productName),
    );
    if (selected == null || !mounted) return;
    widget.onChanged(
      ProductPhotoSelection(
        path: selected.imageUrl,
        credit: selected.credit,
        pageUrl: selected.pageUrl,
      ),
    );
  }

  Future<void> _pickAndUpload() async {
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1400,
        maxHeight: 1400,
        imageQuality: 82,
      );
      if (image == null || !mounted) return;
      final extension = image.name.split('.').last.toLowerCase();
      const mimeTypes = <String, String>{
        'jpg': 'image/jpeg',
        'jpeg': 'image/jpeg',
        'png': 'image/png',
        'webp': 'image/webp',
      };
      final mimeType = mimeTypes[extension];
      if (mimeType == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Choisis une image JPG, PNG ou WebP.')),
        );
        return;
      }
      final bytes = await image.readAsBytes();
      if (bytes.length > 5 * 1024 * 1024) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Cette photo dépasse 5 Mo. Choisis une image plus légère.',
            ),
          ),
        );
        return;
      }
      setState(() => _uploading = true);
      final path =
          '${widget.businessId}/${DateTime.now().microsecondsSinceEpoch}.$extension';
      await Supabase.instance.client.storage
          .from('product-images')
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              cacheControl: '3600',
              upsert: false,
              contentType: mimeType,
            ),
          );
      if (!mounted) return;
      widget.onChanged(ProductPhotoSelection(path: path));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Photo ajoutée et synchronisée.')),
      );
    } catch (error) {
      if (!mounted) return;
      debugPrint('Téléversement de la photo produit impossible : $error');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Photo non enregistrée. Vérifie que le stockage des photos est activé dans Supabase.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 84,
          height: 84,
          child: widget.photoPath == null
              ? Container(
                  color: const Color(0xFFE9EDF7),
                  child: const Icon(
                    Icons.add_photo_alternate_outlined,
                    color: navy,
                    size: 32,
                  ),
                )
              : _ProductImage(
                  path: widget.photoPath!,
                  fallback: Container(
                    color: const Color(0xFFE9EDF7),
                    child: const Icon(
                      Icons.image_not_supported_outlined,
                      color: navy,
                    ),
                  ),
                ),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            OutlinedButton.icon(
              onPressed: _uploading ? null : _pickAndUpload,
              icon: _uploading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      widget.photoPath == null
                          ? Icons.add_photo_alternate_outlined
                          : Icons.change_circle_outlined,
                    ),
              label: Text(
                _uploading
                    ? 'Envoi de la photo…'
                    : widget.photoPath == null
                    ? 'Ajouter une photo'
                    : 'Changer la photo',
              ),
            ),
            const SizedBox(height: 4),
            OutlinedButton.icon(
              onPressed: _uploading ? null : _searchOnline,
              icon: const Icon(Icons.travel_explore_rounded),
              label: const Text('Rechercher une photo en ligne'),
            ),
            if (widget.photoCredit != null && widget.photoPageUrl != null)
              TextButton.icon(
                onPressed: () => _openPhotoCredit(widget.photoPageUrl),
                icon: const Icon(Icons.info_outline_rounded, size: 17),
                label: const Text('Informations sur la photo'),
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
              ),
            Text(
              widget.photoPath?.startsWith('https://') == true
                  ? 'Photo en ligne • informations conservées avec le produit'
                  : 'Photo depuis l’appareil • JPG, PNG ou WebP • 5 Mo max',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: Colors.black54),
            ),
            if (widget.photoPath != null)
              TextButton.icon(
                onPressed: _uploading ? null : () => widget.onChanged(null),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Retirer la photo'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFB84A52),
                  padding: EdgeInsets.zero,
                ),
              ),
          ],
        ),
      ),
    ],
  );

  Future<void> _openPhotoCredit(String? url) async {
    if (url == null || url.isEmpty) return;
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }
}

class OnlineImageSearchDialog extends StatefulWidget {
  const OnlineImageSearchDialog({super.key, required this.initialQuery});
  final String initialQuery;
  @override
  State<OnlineImageSearchDialog> createState() =>
      _OnlineImageSearchDialogState();
}

class _OnlineImageSearchDialogState extends State<OnlineImageSearchDialog> {
  late final TextEditingController _query = TextEditingController(
    text: widget.initialQuery,
  );
  bool _loading = false;
  String? _error;
  List<OnlineProductPhoto> _photos = [];

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _query.text.trim();
    if (query.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
      _photos = [];
    });
    try {
      final response = await Supabase.instance.client.functions.invoke(
        'product-image-search',
        body: {'query': query},
      );
      final data = response.data;
      if (data is! Map || data['photos'] is! List) {
        throw Exception('Réponse de recherche invalide');
      }
      final photos = (data['photos'] as List)
          .whereType<Map>()
          .map(
            (item) =>
                OnlineProductPhoto.fromJson(Map<String, dynamic>.from(item)),
          )
          .where((photo) => photo.imageUrl.isNotEmpty)
          .toList();
      if (!mounted) return;
      setState(() {
        _photos = photos;
        if (photos.isEmpty) _error = 'Aucune photo trouvée. Essaie un autre mot, en français ou en anglais.';
      });
    } catch (error) {
      if (!mounted) return;
      debugPrint('Recherche de photo impossible : $error');
      setState(
        () => _error = 'Recherche indisponible. Vérifie que la fonction product-image-search est déployée dans Supabase.',
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _search());
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Rechercher une photo de produit'),
    content: SizedBox(
      width: _dialogWidth(context, 620),
      height: _dialogHeight(context, 470),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _query,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _search(),
                  decoration: const InputDecoration(
                    hintText: 'Ex. : sac de riz, savon, chaussures',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                onPressed: _loading ? null : _search,
                icon: const Icon(Icons.search),
                tooltip: 'Rechercher',
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Choisis une photo qui correspond au produit. Les informations de licence restent accessibles avec le bouton ⓘ.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(_error!, textAlign: TextAlign.center),
                    ),
                  )
                : GridView.builder(
                    itemCount: _photos.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          childAspectRatio: .9,
                        ),
                    itemBuilder: (context, index) {
                      final photo = _photos[index];
                      return InkWell(
                        onTap: () => Navigator.pop(context, photo),
                        child: Card(
                          clipBehavior: Clip.antiAlias,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.network(
                                photo.imageUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Center(
                                  child: Icon(Icons.broken_image_outlined),
                                ),
                              ),
                              Positioned(
                                right: 6,
                                top: 6,
                                child: Material(
                                  color: Colors.white.withValues(alpha: .94),
                                  shape: const CircleBorder(),
                                  child: IconButton(
                                    tooltip: 'Informations sur la photo',
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () =>
                                        _openPhotoInfo(photo.pageUrl),
                                    icon: const Icon(
                                      Icons.info_outline_rounded,
                                      size: 19,
                                      color: navy,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Fermer'),
      ),
    ],
  );

  Future<void> _openPhotoInfo(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }
}

class _ProductImage extends StatelessWidget {
  const _ProductImage({required this.path, required this.fallback});
  final String path;
  final Widget fallback;
  @override
  Widget build(BuildContext context) => path.startsWith('https://')
      ? Image.network(
          path,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => fallback,
        )
      : _StoredProductPhoto(path: path, fallback: fallback);
}

class _StoredProductPhoto extends StatefulWidget {
  const _StoredProductPhoto({required this.path, required this.fallback});
  final String path;
  final Widget fallback;

  @override
  State<_StoredProductPhoto> createState() => _StoredProductPhotoState();
}

class _StoredProductPhotoState extends State<_StoredProductPhoto> {
  late Future<String> _url = _createUrl(widget.path);

  Future<String> _createUrl(String path) => Supabase.instance.client.storage
      .from('product-images')
      .createSignedUrl(path, 604800);

  @override
  void didUpdateWidget(covariant _StoredProductPhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) _url = _createUrl(widget.path);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String>(
    future: _url,
    builder: (context, snapshot) {
      if (!snapshot.hasData) return widget.fallback;
      return Image.network(
        snapshot.data!,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stack) => widget.fallback,
      );
    },
  );
}

class AddProductDialog extends StatefulWidget {
  const AddProductDialog({
    super.key,
    required this.businessId,
    this.existingUnits = const {},
    this.existingBarcodes = const {},
  });
  final String businessId;
  final Set<String> existingUnits;
  final Set<String> existingBarcodes;

  @override
  State<AddProductDialog> createState() => _AddProductDialogState();
}

class _AddProductDialogState extends State<AddProductDialog> {
  final formKey = GlobalKey<FormState>();
  DateTime? expirationDate;
  final name = TextEditingController();
  final barcode = TextEditingController();
  final quantity = TextEditingController(text: '0');
  final purchase = TextEditingController();
  final wholesale = TextEditingController();
  final retail = TextEditingController();
  final market = TextEditingController();
  final lowStock = TextEditingController(text: '2');
  final conversion = TextEditingController(text: '1');
  final customStockUnit = TextEditingController();
  final customRetailUnit = TextEditingController();
  String category = 'Alimentation';
  String unit = 'Sac';
  String retailUnit = 'Sac';
  bool customStockUnitSelected = false;
  bool customRetailUnitSelected = false;
  String? photoPath;
  String? photoCredit;
  String? photoPageUrl;
  String? photoPhotographerUrl;

  double _value(TextEditingController controller) =>
      double.tryParse(controller.text.trim().replaceAll(',', '.')) ?? 0;

  String get _stockUnit =>
      customStockUnitSelected ? customStockUnit.text.trim() : unit;
  String get _saleUnit =>
      customRetailUnitSelected ? customRetailUnit.text.trim() : retailUnit;

  double? get _knownConversion => _stockUnit == 'Soghor' && _saleUnit == 'Kg'
      ? 3
      : _stockUnit == 'Kg' && _saleUnit == 'Soghor'
      ? 1 / 3
      : null;
  double get _unitsPerStockUnit =>
      _saleUnit == _stockUnit ? 1 : _knownConversion ?? _value(conversion);
  double get _minimumRetailPrice => _unitsPerStockUnit <= 0
      ? 0
      : (_value(purchase) / _unitsPerStockUnit).ceilToDouble();
  double get _marginPerRetailUnit => _unitsPerStockUnit <= 0
      ? 0
      : _value(retail) - _value(purchase) / _unitsPerStockUnit;
  double get _estimatedRemainingMargin =>
      _value(quantity) * _unitsPerStockUnit * _marginPerRetailUnit;
  bool get _canShowMargin =>
      _value(purchase) > 0 && _value(retail) > 0 && _unitsPerStockUnit > 0;

  @override
  void dispose() {
    name.dispose();
    barcode.dispose();
    quantity.dispose();
    purchase.dispose();
    wholesale.dispose();
    retail.dispose();
    market.dispose();
    lowStock.dispose();
    conversion.dispose();
    customStockUnit.dispose();
    customRetailUnit.dispose();
    super.dispose();
  }

  double _read(TextEditingController c) =>
      double.parse(c.text.trim().replaceAll(',', '.'));

  String? _validateNumber(String? value, {bool positive = false}) {
    final number = double.tryParse((value ?? '').trim().replaceAll(',', '.'));
    if (number == null || number < 0 || (positive && number == 0)) {
      return positive
          ? 'Saisis un montant supérieur à zéro.'
          : 'Saisis un nombre valide.';
    }
    return null;
  }

  void _save() {
    if (!formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      Product(
        name: name.text.trim(),
        barcode: barcode.text.trim(),
        category: category,
        quantity: _read(quantity),
        unit: _stockUnit,
        retailUnit: _saleUnit,
        retailUnitsPerStockUnit: _saleUnit == _stockUnit
            ? 1
            : _knownConversion ?? _read(conversion),
        purchasePrice: _read(purchase),
        wholesalePrice: _read(wholesale),
        retailPrice: _read(retail),
        lowStockLimit: _read(lowStock),
        expirationDate: expirationDate,
        marketPrice: market.text.trim().isEmpty ? null : _read(market),
        photoPath: photoPath,
        photoCredit: photoCredit,
        photoPageUrl: photoPageUrl,
        photoPhotographerUrl: photoPhotographerUrl,
      ),
    );
  }

  Widget _numberField(
    TextEditingController controller,
    String label, {
    bool optional = false,
  }) => TextFormField(
    controller: controller,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    onChanged: (_) => setState(() {}),
    validator: (value) => optional && (value == null || value.trim().isEmpty)
        ? null
        : _validateNumber(
            value,
            positive:
                controller == purchase ||
                controller == wholesale ||
                controller == retail,
          ),
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
    ),
  );

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Ajouter un produit'),
    content: SizedBox(
      width: _dialogWidth(context, 520),
      child: SingleChildScrollView(
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Informations générales',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: navy,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: name,
                onChanged: (_) => setState(() {}),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Le nom du produit est obligatoire.'
                    : null,
                decoration: const InputDecoration(
                  labelText: 'Nom du produit',
                  hintText: 'Ex. : Riz local',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              _barcodeField(
                context,
                barcode,
                widget.existingBarcodes,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: category,
                decoration: const InputDecoration(
                  labelText: 'Catégorie',
                  border: OutlineInputBorder(),
                ),
                items: const ['Alimentation', 'Divers', 'Boissons', 'Autre']
                    .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                    .toList(),
                onChanged: (value) =>
                    setState(() => category = value ?? category),
              ),
              const SizedBox(height: 12),
              _expirationDatePicker(
                context,
                expirationDate,
                (value) => setState(() => expirationDate = value),
              ),
              const SizedBox(height: 14),
              ProductPhotoSelector(
                businessId: widget.businessId,
                productName: name.text.trim(),
                photoPath: photoPath,
                photoCredit: photoCredit,
                photoPageUrl: photoPageUrl,
                photoPhotographerUrl: photoPhotographerUrl,
                onChanged: (value) => setState(() {
                  photoPath = value?.path;
                  photoCredit = value?.credit;
                  photoPageUrl = value?.pageUrl;
                  photoPhotographerUrl = null;
                }),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: customStockUnitSelected ? _customProductUnitValue : unit,
                decoration: const InputDecoration(
                  labelText: 'Unité de stock',
                  border: OutlineInputBorder(),
                ),
                items: _productUnitItems(extraUnits: widget.existingUnits),
                onChanged: (value) => setState(() {
                  final previousUnit = unit;
                  customStockUnitSelected = value == _customProductUnitValue;
                  if (!customStockUnitSelected && value != null) unit = value;
                  if (_stockUnit == 'Soghor') {
                    retailUnit = 'Kg';
                    customRetailUnitSelected = false;
                    conversion.text = '3';
                  } else {
                    if (retailUnit == previousUnit) retailUnit = unit;
                    conversion.text = _saleUnit == _stockUnit
                        ? '1'
                        : _stockUnit == 'Bidon' && _saleUnit == 'Litre'
                        ? '25'
                        : '1';
                  }
                }),
              ),
              if (customStockUnitSelected) ...[
                const SizedBox(height: 10),
                TextFormField(
                  controller: customStockUnit,
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) => setState(() {}),
                  validator: (value) =>
                      customStockUnitSelected &&
                          (value == null || value.trim().isEmpty)
                      ? 'Saisis le nom de l’unité de stock.'
                      : null,
                  decoration: const InputDecoration(
                    labelText: 'Nom de l’unité de stock',
                    hintText: 'Ex. : Plateau',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: customRetailUnitSelected
                    ? _customProductUnitValue
                    : retailUnit,
                decoration: const InputDecoration(
                  labelText: 'Unité de vente au détail',
                  border: OutlineInputBorder(),
                ),
                items: _productUnitItems(extraUnits: widget.existingUnits),
                onChanged: (value) => setState(() {
                  customRetailUnitSelected = value == _customProductUnitValue;
                  if (!customRetailUnitSelected && value != null) {
                    retailUnit = value;
                  }
                  conversion.text = _saleUnit == _stockUnit
                      ? '1'
                      : _knownConversion?.toString() ??
                            (_stockUnit == 'Bidon' && _saleUnit == 'Litre'
                                ? '25'
                                : '1');
                }),
              ),
              if (customRetailUnitSelected) ...[
                const SizedBox(height: 10),
                TextFormField(
                  controller: customRetailUnit,
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) => setState(() {}),
                  validator: (value) =>
                      customRetailUnitSelected &&
                          (value == null || value.trim().isEmpty)
                      ? 'Saisis le nom de l’unité de vente.'
                      : null,
                  decoration: const InputDecoration(
                    labelText: 'Nom de l’unité de vente',
                    hintText: 'Ex. : Verre',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
              if (_saleUnit != _stockUnit) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: conversion,
                  readOnly: _knownConversion != null,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (_) => setState(() {}),
                  validator: (value) => _saleUnit == _stockUnit
                      ? null
                      : _validateNumber(value, positive: true),
                  decoration: InputDecoration(
                    labelText:
                        'Quantité de ${_saleUnit.toLowerCase()} dans 1 ${_stockUnit.toLowerCase()}',
                    hintText: 'Ex. : 50 si 1 sac = 50 kg',
                    border: const OutlineInputBorder(),
                  ),
                ),
                if (_knownConversion != null)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Conversion fixe : 1 Soghor = 3 kg. Le stock et les ventes utilisent cette équivalence.',
                        style: TextStyle(color: Colors.black54, fontSize: 12),
                      ),
                    ),
                  ),
                if (_stockUnit == 'Bidon' && _saleUnit == 'Litre')
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Suggestion pour un bidon d’huile : 25 litres. Vérifie la capacité inscrite sur le bidon.',
                        style: TextStyle(color: Colors.black54, fontSize: 12),
                      ),
                    ),
                  ),
              ],
              const SizedBox(height: 12),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Prix et coûts',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: navy,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              _numberField(
                purchase,
                'Prix d’achat par ${_stockUnit.toLowerCase()} ($_currencyLabel)',
              ),
              const SizedBox(height: 12),
              _numberField(
                wholesale,
                'Prix de vente en gros par ${_stockUnit.toLowerCase()} ($_currencyLabel)',
              ),
              const SizedBox(height: 12),
              _numberField(
                retail,
                'Prix de vente au détail par ${_saleUnit.toLowerCase()} ($_currencyLabel)',
              ),
              const SizedBox(height: 12),
              _numberField(
                market,
                'Prix du marché par ' +
                    _saleUnit.toLowerCase() +
                    ' (facultatif)',
                optional: true,
              ),
              if (_canShowMargin) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _marginPerRetailUnit >= 0
                        ? const Color(0xFFEAF7F0)
                        : const Color(0xFFFFF0F0),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _marginPerRetailUnit >= 0
                          ? const Color(0xFFCBE9D7)
                          : const Color(0xFFF1D1D4),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _marginPerRetailUnit >= 0
                            ? Icons.trending_up_rounded
                            : Icons.trending_down_rounded,
                        color: _marginPerRetailUnit >= 0
                            ? const Color(0xFF278052)
                            : const Color(0xFFB84A52),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Marge bénéficiaire estimée',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            Text(
                              '${_money(_marginPerRetailUnit)} par ${_saleUnit.toLowerCase()} • ${_money(_estimatedRemainingMargin)} pour le stock actuel',
                              style: TextStyle(
                                color: _marginPerRetailUnit >= 0
                                    ? const Color(0xFF278052)
                                    : const Color(0xFFB84A52),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _marginPerRetailUnit < 0
                        ? const Color(0xFFFFF0F0)
                        : const Color(0xFFF0F4FF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _marginPerRetailUnit < 0
                        ? 'Prix trop bas : le minimum pour couvrir l’achat est ${_money(_minimumRetailPrice)} par ${_saleUnit.toLowerCase()} (soit ${_money(_value(purchase))} par ${_stockUnit.toLowerCase()}).'
                        : 'Prix minimum pour couvrir l’achat : ${_money(_minimumRetailPrice)} par ${_saleUnit.toLowerCase()} (soit ${_money(_value(purchase))} par ${_stockUnit.toLowerCase()}).',
                    style: TextStyle(
                      color: _marginPerRetailUnit < 0
                          ? const Color(0xFFB84A52)
                          : navy,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Stock et inventaire',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: navy,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              _numberField(
                quantity,
                'Quantité initiale en stock (${_unitLabel(_stockUnit)})',
              ),
              const SizedBox(height: 12),
              _numberField(lowStock, 'Alerte de stock bas à partir de'),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Annuler'),
      ),
      FilledButton(onPressed: _save, child: const Text('Enregistrer')),
    ],
  );
}

double _dialogWidth(BuildContext context, double preferredWidth) {
  final availableWidth = MediaQuery.sizeOf(context).width - 80;
  if (availableWidth <= 0) return 0;
  return availableWidth < preferredWidth ? availableWidth : preferredWidth;
}

double _dialogHeight(BuildContext context, double preferredHeight) {
  final availableHeight = MediaQuery.sizeOf(context).height - 160;
  if (availableHeight <= 0) return 0;
  return availableHeight < preferredHeight ? availableHeight : preferredHeight;
}

String _localizedNumber(String value) {
  final isNegative = value.startsWith('-');
  final unsigned = isNegative ? value.substring(1) : value;
  final parts = unsigned.split('.');
  final grouping = _activeLanguageCode == 'en' ? ',' : '\u202f';
  final decimal = _activeLanguageCode == 'en' ? '.' : ',';
  final whole = parts.first.replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (match) => '${match[1]}$grouping',
  );
  final fraction = parts.length > 1 && parts[1].isNotEmpty
      ? '$decimal${parts[1]}'
      : '';
  return '${isNegative ? '-' : ''}$whole$fraction';
}

String _quantity(double value) {
  if (value == value.roundToDouble()) {
    return _localizedNumber(value.toStringAsFixed(0));
  }
  final rounded = value.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '');
  return _localizedNumber(
    rounded.endsWith('.') ? rounded.substring(0, rounded.length - 1) : rounded,
  );
}

String _money(double value) {
  final fractionDigits = switch (_activeCurrencyCode) {
    'AFN' ||
    'ALL' ||
    'BIF' ||
    'CLP' ||
    'COP' ||
    'DJF' ||
    'GNF' ||
    'HUF' ||
    'IDR' ||
    'IQD' ||
    'IRR' ||
    'ISK' ||
    'JPY' ||
    'KMF' ||
    'KPW' ||
    'KRW' ||
    'LAK' ||
    'LBP' ||
    'MGA' ||
    'MMK' ||
    'PYG' ||
    'RWF' ||
    'SOS' ||
    'SYP' ||
    'UGX' ||
    'VND' ||
    'VUV' ||
    'XAF' ||
    'XOF' ||
    'XPF' ||
    'YER' => 0,
    'BHD' || 'JOD' || 'KWD' || 'LYD' || 'OMR' || 'TND' => 3,
    _ => 2,
  };
  return '${_localizedNumber(value.toStringAsFixed(fractionDigits))} $_currencyLabel';
}

class _BizPageHero extends StatelessWidget {
  const _BizPageHero({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.action,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final narrow = constraints.maxWidth < 620;
      final heading = Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .16),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: Colors.white.withValues(alpha: .2)),
            ),
            child: Icon(icon, color: Colors.white, size: 25),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    height: 1.15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .84),
                    fontSize: 13,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
      final decoratedAction = action == null
          ? const SizedBox.shrink()
          : Theme(
              data: Theme.of(context).copyWith(
                filledButtonTheme: FilledButtonThemeData(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: navy,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 13,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13),
                    ),
                  ),
                ),
              ),
              child: action!,
            );
      return Container(
        width: double.infinity,
        padding: EdgeInsets.all(narrow ? 17 : 22),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1E2C86), Color(0xFF087F78)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: navy.withValues(alpha: .14),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: narrow && action != null
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  heading,
                  const SizedBox(height: 14),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: decoratedAction,
                  ),
                ],
              )
            : Row(
                children: [
                  Expanded(child: heading),
                  if (action != null) ...[
                    const SizedBox(width: 16),
                    decoratedAction,
                  ],
                ],
              ),
      );
    },
  );
}

class SummaryCard extends StatelessWidget {
  const SummaryCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE8EDEF)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, color: color, size: 21),
            ),
            Text(
              value,
              style: const TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.bold,
                color: ink,
              ),
            ),
            Text(title, style: const TextStyle(color: Colors.black54)),
          ],
        ),
      ),
    );
  }
}
