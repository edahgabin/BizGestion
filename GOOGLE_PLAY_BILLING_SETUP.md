# Mise en service des abonnements Google Play — BizGestion

Identifiant Android retenu : `com.bizgestion.app`.
Vérifier qu’il est accepté par Play Console avant de créer la fiche de production. Une fois l’application publiée, cet identifiant ne doit plus changer.

## Produits d’abonnement

Créer dans Play Console les quatre abonnements avec ces identifiants exacts :

- `bizgestion_commerce_monthly` — forfait Commerce, base plan mensuel.
- `bizgestion_commerce_annual` — forfait Commerce, base plan annuel.
- `bizgestion_entreprise_monthly` — forfait Entreprise, base plan mensuel.
- `bizgestion_entreprise_annual` — forfait Entreprise, base plan annuel.

Configurer les pays, périodes et tarifs dans Play Console. L’application récupère le prix local depuis Google Play.

## Connexion sécurisée à Google Play Developer API

1. Dans Google Cloud, activer Google Play Android Developer API pour le projet associé à Play Console.
2. Créer un compte de service et lui donner l’accès à l’application dans Play Console, avec les droits nécessaires pour lire les abonnements et commandes.
3. Créer une clé JSON pour ce compte de service. Ne pas la placer dans le code, dans Flutter, ni dans un dépôt public.
4. Dans Supabase Edge Function Secrets, définir :
   - `ANDROID_PACKAGE_NAME` = `com.bizgestion.app`
   - `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` = le contenu complet de la clé JSON
5. Exécuter `supabase_google_play_subscriptions.sql` dans le SQL Editor Supabase.
6. Déployer `verify-google-play-subscription` avec le CLI Supabase lié au projet BizGestion.
7. Tester l’achat et la restauration depuis une piste de test Play, avec un compte testeur autorisé.

La fonction Supabase vérifie le token auprès de Google, confirme le rôle de propriétaire, puis active le forfait. Elle ne conserve que l’empreinte SHA-256 du token d’achat.

## Avant la publication

Configurer les notifications temps réel d’abonnement Google (RTDN) et leur traitement côté serveur pour synchroniser renouvellements, annulations, remboursements et expirations. La vérification après achat est déjà en place, mais les RTDN restent à raccorder avant la mise en production.

Générer et sauvegarder la clé de signature d’envoi Android hors du dépôt. Installer le JDK et Android SDK, puis générer un Android App Bundle signé (`.aab`). Ne jamais perdre la clé de signature ou son mot de passe.
