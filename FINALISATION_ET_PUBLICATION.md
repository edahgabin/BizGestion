# Finalisation et publication de BizGestion

## Mise à jour Supabase

1. Ouvre le projet **BizGestion-dev**, puis **SQL Editor**.
2. Ouvre le fichier `supabase_business_normalization.sql` du dossier BizGestion et copie tout son contenu dans une requête SQL neuve.
3. Clique sur **Run**. Cette migration ajoute ou remplace les fonctions de synchronisation et le miroir indexé; elle ne supprime pas les données de `business_data`.
4. Dans une autre requête, exécute tout le contenu de `supabase_launch_checks.sql`.
5. Vérifie que chaque contrôle est à `true`. En particulier, « RPC de sauvegarde par modifications » doit être vrai.

Ne publie pas le nouveau site avant cette migration : la version Web inclut maintenant la sauvegarde des seules lignes modifiées pour les propriétaires et administrateurs.

## Publication Web gratuite

Le nouveau site compilé se trouve dans `build/web` et sa copie prête à déposer dans Netlify se trouve ici :

`C:\Users\hp\Documents\Codex\BizGestion-web-release-20261024-v2`

Tu peux aussi déposer l’archive `C:\Users\hp\Documents\Codex\BizGestion-web-release-20261024-v2.zip` dans Netlify Drop. Pour mettre à jour ton site, connecte-toi à Netlify et dépose le dossier ou l’archive dans le site Netlify existant. Un sous-domaine gratuit `netlify.app` suffit; aucun domaine payant n’est nécessaire.

Après publication, ouvre le lien du site et vérifie la connexion, le commerce actif, une vente et la synchronisation depuis un second appareil si possible.

## Ce qui fonctionne sans frais supplémentaires

- Une invitation d’équipe peut être préparée dans BizGestion puis transmise par le lien proposé, par WhatsApp ou autrement. Il n’est pas nécessaire d’acheter un domaine ni un service d’envoi de courriels.
- Les photos peuvent être recherchées dans les sources gratuites déjà configurées; le déploiement de la fonction de recherche reste nécessaire dans **Supabase > Edge Functions** si elle n’y est pas encore publiée.
- L’essai et les limites par forfait sont prêts dans le code et le schéma SQL.

## Abonnement et paiement au Bénin

Tarifs de lancement proposés et affichés dans BizGestion : **Découverte gratuit**, **Commerce à 2 500 FCFA/mois ou 25 000 FCFA/an**, **Entreprise à 7 500 FCFA/mois ou 75 000 FCFA/an**. Les tarifs annuels correspondent à dix mensualités. Pour un commerce réglé dans une autre devise, l’application affiche une conversion indicative à partir du dernier taux de référence disponible; elle garde le résultat en cache et indique la date et la source. XOF et XAF restent au tarif FCFA. Ces prix sont une proposition commerciale pour le Bénin, pas encore des tarifs encaissés : le paiement en ligne et le changement automatique de forfait restent désactivés. Le montant converti est informatif et ne préjuge pas des devises acceptées par le futur prestataire.

FedaPay est une option à étudier : son tarif publié indique **aucun frais tant qu’aucun paiement n’est reçu**, puis 1,8 % pour MTN, Moov et Celtiis au Bénin, et 3,6 % pour Visa/Mastercard. Ses conditions pour un marchand béninois demandent notamment un IFU professionnel, un compte bancaire ou Mobile Money professionnel, une adresse e-mail active et une application ou un site opérationnel. Consulte les [tarifs FedaPay](https://www.fedapay.com/pricing), les [conditions marchands](https://www.fedapay.com/general-terms-of-use) et la [liste des pays pris en charge](https://support.fedapay.com/portal/en/kb/articles/fedapay-fonctionne-t-il-dans-mon-pays) avant de créer un compte; les exigences et taux peuvent évoluer.

PayDunya constitue une autre piste : sa page tarifaire indique l’absence d’abonnement et de frais d’installation, avec une commission par transaction. Consulte ses [frais officiels](https://paydunya.com/service-fees) et sa [FAQ](https://paydunya.com/faq) pour les moyens de paiement et les justificatifs requis au Bénin.

La documentation FedaPay consultée décrit la création de transactions, les liens de paiement et les webhooks signés, mais ne confirme pas ici un prélèvement récurrent mensuel. Tant que le prestataire ne confirme pas ce mécanisme et tant qu’un compte marchand n’est pas ouvert, il faut considérer le paiement comme un règlement ponctuel à renouveler manuellement. Aucun prestataire n’est encore intégré à BizGestion.

## Autres éléments non activés

- **Paiements d’abonnement** : aucun prestataire ni encaissement automatique n’est configuré. Les tarifs de lancement proposés sont affichés dans l’application, mais aucune somme n’est prélevée. Il faudra vérifier l’éligibilité, ouvrir le compte marchand, obtenir les clés et brancher puis tester les paiements avant d’activer la facturation.
- **Très grande échelle** : les écritures cloud des propriétaires et administrateurs envoient désormais les changements au lieu de renvoyer chaque ligne. Toutefois, le chargement initial et le cache hors ligne conservent encore toutes les données, et le snapshot historique reste reconstruit côté serveur. Ne présente donc pas encore l’application comme testée pour des volumes illimités.
- **État de production** : la migration SQL et la nouvelle version Netlify ne sont confirmées qu’après leurs exécutions dans les comptes concernés. La compilation locale ne les publie pas automatiquement.
