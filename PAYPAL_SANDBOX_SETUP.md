# Mise en service des abonnements PayPal BizGestion (Sandbox)

Les tarifs fixes des abonnements sont en USD :

- Commerce : 4 USD/mois ou 40 USD/an
- Entreprise : 12 USD/mois ou 120 USD/an

Les quatre nouveaux plans ont été créés et activés dans PayPal Sandbox sous le
compte vendeur de test du Lesotho. Les deux anciens plans Commerce restent
désactivés. La devise des transactions du commerce reste indépendante de celle
de l’abonnement.

Les fonctions sont prêtes dans `supabase/functions/`. Elles restent désactivées dans l’interface tant que `PAYPAL_SANDBOX_ENABLED` n’est pas activé au lancement de Flutter. Aucun paiement réel n’est effectué en Sandbox.

## 1. Ajouter la table de correspondance

Dans le tableau de bord Supabase du projet BizGestion-dev, ouvre **SQL Editor**, crée une requête, colle le contenu de `supabase_paypal_subscriptions.sql`, puis clique **Run**.

## 2. Déployer les fonctions Supabase

Déploie les deux dossiers en tant que fonctions Edge, en conservant exactement ces noms :

- `create-paypal-subscription`
- `paypal-subscription-webhook`

La première exige une session connectée. La seconde doit accepter les appels PayPal sans JWT Supabase, mais vérifie la signature PayPal elle-même.

## 3. Ajouter les secrets PayPal dans Supabase

Dans **Edge Functions → Secrets**, ajoute :

- `PAYPAL_ENV` = `sandbox`
- `PAYPAL_CLIENT_ID` = Client ID Sandbox de `BizGestion-Lesotho-Test`
- `PAYPAL_CLIENT_SECRET` = Secret Sandbox de cette même application
- `PAYPAL_COMMERCE_MONTHLY_PLAN_ID` = `P-4R319063TG409954ENLPZO5Q`
- `PAYPAL_COMMERCE_ANNUAL_PLAN_ID` = `P-8D157784FH564071ANLP5X5A`
- `PAYPAL_ENTREPRISE_MONTHLY_PLAN_ID` = `P-679691538D547215DNLPZRIY`
- `PAYPAL_ENTREPRISE_ANNUAL_PLAN_ID` = `P-90P18188NC497794GNLP5W4A`
- `PAYPAL_RETURN_ORIGINS` = `https://peaceful-seahorse-c8bdc5.netlify.app,http://localhost:5000,http://127.0.0.1:5000`

Saisis le Client Secret directement dans Supabase. Ne le mets ni dans Flutter, ni dans Netlify, ni dans un message.

## 4. Configurer les notifications PayPal

Dans l’application Sandbox PayPal, ajoute un webhook avec cette URL :

`https://kxrmmyhqjvihrabmmgoa.supabase.co/functions/v1/paypal-subscription-webhook`

Sélectionne les événements suivants :

- `BILLING.SUBSCRIPTION.ACTIVATED`
- `BILLING.SUBSCRIPTION.CANCELLED`
- `BILLING.SUBSCRIPTION.SUSPENDED`
- `BILLING.SUBSCRIPTION.EXPIRED`
- `BILLING.SUBSCRIPTION.PAYMENT.FAILED`
- `PAYMENT.SALE.COMPLETED`

Le Webhook ID de la nouvelle application est `0AM71913C34857025`. Il doit être enregistré dans Supabase sous `PAYPAL_WEBHOOK_ID`. Redéploie ensuite `paypal-subscription-webhook` si le tableau de bord ne recharge pas automatiquement ses secrets.

## 5. Afficher les boutons de test localement

Dans le terminal, depuis le dossier `bizgestion`, lance :

```powershell
flutter run -d chrome --web-port 5000 --dart-define=PAYPAL_SANDBOX_ENABLED=true
```

Utilise un compte acheteur Personal Sandbox, pas ton compte réel. Après l’approbation, PayPal renvoie vers BizGestion et le webhook met à jour le statut. Le déploiement Netlify habituel garde les boutons de paiement cachés tant que le paramètre de test n’est pas explicitement fourni.

## Préparer le passage en production

Le code accepte maintenant deux configurations isolées : les noms existants `PAYPAL_*` restent réservés à Sandbox, tandis que les secrets `PAYPAL_LIVE_*` ci-dessous sont réservés au réel. La fonction choisit son environnement avec `PAYPAL_ENV`. Elle ne reprend jamais les identifiants ni les plans Sandbox lorsque `PAYPAL_ENV=live`.

Avant d’activer les paiements réels :

1. Dans Supabase **SQL Editor**, exécute à nouveau le fichier mis à jour `supabase_paypal_subscriptions.sql`. Il ajoute l’identification de l’environnement aux abonnements Sandbox/Live.
2. Dans le tableau de bord PayPal **Live**, crée et active quatre nouveaux plans dans le compte vendeur réel, en USD : Commerce mensuel 4 USD, Commerce annuel 40 USD avec fréquence **1 Year**, Entreprise mensuel 12 USD et Entreprise annuel 120 USD avec fréquence **1 Year**. Les ID `P-...` Sandbox ne peuvent pas servir en Live.
3. Ouvre **Apps & Credentials → Live**, sélectionne l’application BizGestion et relève son Client ID et son Secret Live. Ne les envoie pas dans la conversation et ne les ajoute pas au code ou à Flutter.
4. Dans cette même application Live, crée un webhook vers `https://kxrmmyhqjvihrabmmgoa.supabase.co/functions/v1/paypal-subscription-webhook`, choisis les six événements listés à l’étape 4, puis relève le **Webhook ID Live**. L’ID de webhook Sandbox ne peut pas vérifier les notifications Live.
5. Dans Supabase → **Edge Functions → Secrets**, ajoute ces secrets Live :

   - `PAYPAL_LIVE_CLIENT_ID`
   - `PAYPAL_LIVE_CLIENT_SECRET`
   - `PAYPAL_LIVE_WEBHOOK_ID`
   - `PAYPAL_LIVE_COMMERCE_MONTHLY_PLAN_ID`
   - `PAYPAL_LIVE_COMMERCE_ANNUAL_PLAN_ID`
   - `PAYPAL_LIVE_ENTREPRISE_MONTHLY_PLAN_ID`
   - `PAYPAL_LIVE_ENTREPRISE_ANNUAL_PLAN_ID`
   - `PAYPAL_LIVE_RETURN_ORIGINS` = l’adresse publique HTTPS de BizGestion, par exemple `https://peaceful-seahorse-c8bdc5.netlify.app`

   Garde les valeurs secrètes dans Supabase. Ne remplace pas les secrets Sandbox : ajoute ces noms Live séparément. N’active pas encore `PAYPAL_ENV=live`.
6. Résilie les abonnements d’essai dans le compte PayPal **Sandbox**. Puis exécute une fois `supabase_paypal_live_cutover.sql` dans le SQL Editor : il remet à l’essai les forfaits uniquement associés à des abonnements Sandbox et conserve les dates d’essai ainsi que l’historique des liens. Cela évite qu’un ancien abonnement de test soit considéré comme un forfait payé en production.
7. Configure `PAYPAL_ENV` = `live`, puis redéploie `create-paypal-subscription` et `paypal-subscription-webhook`. Cette variable est commune aux deux fonctions : elles fonctionneront toutes deux en Live et les essais Sandbox seront suspendus jusqu’au retour à `sandbox`. Les fonctions vérifient le prix, la devise, la fréquence, le statut actif et le nom du plan avant de préparer un paiement.
8. Une fois le compte vendeur habilité et les quatre plans Live vérifiés, construis la version Web avec `flutter build web --dart-define=PAYPAL_LIVE_ENABLED=true`, puis publie le dossier `build/web`. Pour un APK Android, utilise `flutter build apk --release --dart-define=PAYPAL_LIVE_ENABLED=true`. Ne combine pas ce paramètre avec `PAYPAL_SANDBOX_ENABLED=true`. Le mode Live affiche un avertissement de facturation réelle et le serveur refuse toute version qui demande l’environnement opposé.

PayPal classe le Lesotho parmi les pays autorisés à envoyer, recevoir et retirer des fonds, mais cela ne garantit pas à lui seul que les abonnements récurrents sont activés pour ce compte marchand ou cette application. Confirme cette capacité dans le tableau de bord Live et avec un appel API réussi avant de diffuser la version. Les paiements Live peuvent débiter de vrais clients.
