# YTTranscript

Application macOS native qui extrait les sous-titres d'une vidéo YouTube et
produit un transcript `.txt` propre, optimisé pour être lu par une IA avec,
pour les vidéos en anglais, des sous-titres `.srt` traduits automatiquement.

## Fonctionnalités

- **Extraction en un clic** : coller l'URL, appuyer sur Extraire.
- **Transcript `.txt` propre** : en-tête (titre, chaîne, durée, URL),
  timestamps, chapitres YouTube, déduplication des artefacts des
  sous-titres auto-générés.
- **Traduction `.srt`** : vidéos anglaises traduites à la volée
  (framework Apple Translation, 100 % on-device — aucun compte, aucune API).
  10 langues cibles au choix.
- **Un dossier par vidéo** : `Transcripts/<titre>/` contenant le `.txt`
  et le `.srt`.
- **Historique** : extractions récentes, détection des fichiers supprimés,
  avertissement si une vidéo a déjà été extraite.

## Prérequis

- macOS 15 ou plus récent, Apple Silicon
- [Homebrew](https://brew.sh), puis :

```sh
brew install yt-dlp ffmpeg
```

## Build

Aucun Xcode requis — les Command Line Tools suffisent :

```sh
xcode-select --install   # si pas déjà fait
./build.sh
open build/YTTranscript.app
```

> `build.sh` contourne un bug connu des CLT 26.x
> (« redefinition of module 'SwiftBridging' ») via un overlay VFS.

## Utilisation

1. Lancer l'app, coller une URL YouTube (bouton **Coller** ou pré-remplissage
   automatique depuis le presse-papier).
2. **Extraire**. Le `.txt` est écrit immédiatement ; la traduction `.srt`
   suit en arrière-plan (annulable, progression affichée).
3. **Reveal in Finder** ouvre le dossier ; **Copier** met le transcript
   dans le presse-papier.

Sortie type :

```
Titre : Why Some Projects Use Multiple Programming Languages
Chaîne : Core Dumped
Durée : 19:32
URL : https://www.youtube.com/watch?v=XJC5WB2Bwrc

== Introduction ==
[00:01] This video was sponsored by...
```

## Tests

```sh
./test.sh
```

Tests unitaires du parseur VTT (timestamps, déduplication, regroupement SRT)
et des utilitaires (noms de fichiers, IDs YouTube).

## Limites

- La qualité dépend des sous-titres YouTube ; les auto-générés restent
  imparfaits.
- Traduction : anglais → langue cible uniquement.
- Une vidéo à la fois (pas de playlists).
- Usage personnel : app non signée/notarisée.

## Maintenance

YouTube change régulièrement son format. En cas d'échec d'extraction,
mettre à jour yt-dlp (bouton dans l'app, ou `brew upgrade yt-dlp`).

(Developper avec Claude Fable 5)
