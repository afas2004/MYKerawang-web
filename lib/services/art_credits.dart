import 'package:flutter/foundation.dart';

/// Adds the bundled art to Flutter's licences page (Settings → Open-source
/// credits), next to the packages. The WP25 Malaysia drawings are CC BY 4.0
/// and must be credited; the rest are credited as a courtesy.
/// Full list: assets/brand/LICENSE.md and assets/illustrations/LICENSE.md.
void registerArtCredits() {
  LicenseRegistry.addLicense(() async* {
    yield const LicenseEntryWithLineBreaks(['Malaysian stitch illustrations (WP25 Malaysia)'], '''
Wau Bulan, Wau Kucing, Wau Jala Budi, Nasi Lemak and Sape illustrations by Geleparaplu for Wikimedia Malaysia (Wikipedia 25), from Wikimedia Commons.

Licensed under Creative Commons Attribution 4.0 International (CC BY 4.0), https://creativecommons.org/licenses/by/4.0/

Changes: recoloured, metadata removed, coordinates rounded.''');
    yield const LicenseEntryWithLineBreaks(['Songket pattern'], '''
"Malay songket pattern - Perseri" by EmpAhmadK, Wikimedia Commons. CC0 1.0 (public domain).''');
    yield const LicenseEntryWithLineBreaks(['Open Peeps, Open Doodles'], '''
Illustrations by Pablo Stanley, openpeeps.com and opendoodles.com. CC0 1.0 (public domain).''');
    yield const LicenseEntryWithLineBreaks(['Fluent Emoji'], '''
MIT License

Copyright (c) Microsoft Corporation.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.''');
  });
}
