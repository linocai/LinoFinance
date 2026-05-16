# LinoFinance Frontend

Swift package for shared iOS/macOS code. The app shell will be added as an Xcode
project after the shared modules stabilize.

## Modules

- `LinoFinanceCore`: API client, shared models, confirmed defaults.
- `LinoFinanceDesignSystem`: SwiftUI primitives such as `MoneyText`, `StatusTag`,
  and `CurrencyBadge`.
- `LinoFinanceFeatures`: feature-level placeholder views that compose core and
  design-system modules.

## Local Check

```bash
cd frontend
swift test
```

