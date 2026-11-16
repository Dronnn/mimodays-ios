# App Store Connect checklist

App: MimoDays (`com.mrmaier.MimoDays`, App Store Connect app ID 6835025354).

## Tips (consumable in-app purchases) - 2026-11-16

| Product ID | Apple ID | US base |
| --- | --- | ---: |
| `com.mrmaier.MimoDays.tip.small` | 6835420798 | $2.99 |
| `com.mrmaier.MimoDays.tip.medium` | 6835420962 | $4.99 |
| `com.mrmaier.MimoDays.tip.large` | 6835420909 | $7.99 |
| `com.mrmaier.MimoDays.tip.generous` | 6835421004 | $19.99 |
| `com.mrmaier.MimoDays.tip.patron` | 6835420809 | $49.99 |
| `com.mrmaier.MimoDays.tip.extraordinary` | 6835420927 | $99.99 |

- [x] Created, consumable, not family-shared; review note "A voluntary tip in Settings > Donations. It unlocks nothing; no feature is gated."
- [x] en-US name and description "Keeps MimoDays independent. It unlocks nothing." (55-character limit; the StoreKit file matches)
- [x] Available in all 175 territories and new ones
- [x] Prices: US base; 19 manual prices (upper-middle, lower-middle and low groups, equalized from the US targets); BGD and ETH have no price points and stay automatic; 156 automatic
- [x] Review screenshot `IAP/Review-D01.png` (D01 from the UI test), delivery COMPLETE
- [x] State: READY_TO_SUBMIT (re-read after every write)
- [ ] Submitted with the first app version (16.5) - only with Andrew's go-ahead
- Promotional images (`IAP/Tip-*.png`, 1024 px) not uploaded: only needed to promote the tips on the App Store
