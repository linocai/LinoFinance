# LinoFinance Frontend

Swift package for shared iOS/macOS code plus the real Xcode macOS app project.

## Modules

- `LinoFinanceCore`: API client, shared models, confirmed defaults.
- `LinoFinanceDesignSystem`: SwiftUI primitives such as `MoneyText`, `StatusTag`,
  and `CurrencyBadge`.
- `LinoFinanceFeatures`: feature-level placeholder views that compose core and
  design-system modules.
- `LinoFinance.xcodeproj`: macOS app target `LinoFinance`, bundle id
  `com.lino.linofinance`, built from `frontend/LinoFinance/`.

## Local Check

```bash
cd frontend
swift test
```

## Build Local macOS App

```bash
xcodebuild \
  -project LinoFinance.xcodeproj \
  -scheme LinoFinance \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath .derivedData \
  build
open .derivedData/Build/Products/Debug/LinoFinance.app
```

The packaged app defaults to the deployed backend at `https://lf.linotsai.top/api/v1`.

For local testing, override the API endpoint when launching the app:

```bash
LINOFINANCE_API_BASE_URL=http://127.0.0.1:6868/api/v1 \
LINOFINANCE_API_TOKEN=replace-with-local-token-if-needed \
open .derivedData/Build/Products/Debug/LinoFinance.app
```

The app also reads `linofinance.apiBaseURL` and `linofinance.apiToken` from
`UserDefaults` for local testing.
