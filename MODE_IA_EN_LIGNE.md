# Activer le mode IA en ligne de BizGestion

Le mode local continue de fonctionner sans connexion. Le mode en ligne est facultatif et réservé au propriétaire du commerce; les employés gardent l’assistant local hors ligne. Le propriétaire l’active avant de poser sa question. BizGestion envoie à OpenAI la question et un résumé des ventes par période et par produit, achats, stock, crédits clients, paiements, dépenses, remboursements et mouvements de caisse. Le résumé ne contient pas les noms ou les numéros de téléphone des clients.

Les quotas sont de **5 demandes par jour** pour les comptes gratuits, **1 695 demandes par mois** pour un abonnement Commerce actif et **2 825 demandes par mois** pour un abonnement Entreprise actif. Les plafonds abonnés correspondent à une estimation des enveloppes API de 300 FCFA et 500 FCFA par mois, basée sur une question-type; ce ne sont pas des plafonds monétaires exacts. Le coût réel varie avec les tokens réellement envoyés et générés. La fonction n’envoie à OpenAI qu’un résumé calculé côté serveur, avec un maximum de 400 jetons de réponse. Définir aussi un plafond de dépenses dans OpenAI avant d’activer le secret.

## Déploiement après une modification de l’IA

1. Dans le projet Supabase lié à BizGestion, ouvre **SQL Editor**, colle le contenu actuel de `supabase_business_ai.sql`, puis exécute-le. Cette fonction vérifie aussi que le demandeur est le propriétaire.
2. Depuis la racine du projet, déploie la fonction mise à jour :

   ```powershell
   .\node_modules\.bin\supabase.cmd functions deploy bizgestion-ai
   ```

3. Garde le secret `OPENAI_API_KEY` déjà configuré dans Supabase. S’il manque, ajoute-le dans les secrets des Edge Functions avec une clé API OpenAI. Ne mets jamais cette clé dans Flutter, dans Cloudflare Pages ou dans le dépôt de code.
4. Facultatif : ajoute `OPENAI_MODEL` pour choisir un modèle disponible sur le compte. Sans cette variable, la fonction utilise `gpt-6-luna`.
5. Configure un plafond de dépenses dans le compte API OpenAI.
6. Pour les changements Flutter, reconstruis le site puis redéploie le contenu de `build/web` sur Cloudflare Pages. Le déploiement de la fonction Supabase ne met pas à jour l’interface Flutter.

Si la clé ou le script SQL n’est pas configuré, l’application conserve la réponse locale et affiche que l’IA en ligne est indisponible. Si le quota gratuit de cinq questions est atteint, la réponse locale reste disponible. Le mode IA en ligne n’est jamais activé par défaut. L’assistant local reconnaît aussi les questions sur les ventes d’un produit donné pendant la période sélectionnée, y compris « aujourd’hui » écrit avec une apostrophe.
L’IA répond aux questions ayant un lien plausible avec le commerce. Elle ne refuse que les demandes clairement sans rapport; en cas de doute, elle demande une précision.
