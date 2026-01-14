# Walkthrough - Refactor Main Screen Layout

I have refactored the main screen layout to fix the issue where the flash card grid was partly hidden by the menu buttons.

## Changes

### `lib/main.dart`

I replaced the `Column` layout with a `Stack` layout to allow the content to scroll behind the floating top and bottom bars.

#### Key Changes:

1.  **Removed `SafeArea` Wrapper:** The `Scaffold` body is no longer wrapped in `SafeArea`, allowing content to extend to the screen edges.
2.  **Stack Layout:**
    -   **Layer 1 (Content):** `SingleChildScrollView` is now inside `Positioned.fill`.
        -   Added `padding` to the top and bottom of the scroll view to ensure the first and last items are initially visible and not hidden behind the bars.
        -   `top: appBarTotalHeight + 12.0`
        -   `bottom: bottomBarHeight + bottomSafePadding + 16.0`
    -   **Layer 2 (Top Bar):** Pinned to the top using `Positioned(top: 0, left: 0, right: 0)`.
    -   **Layer 3 (Bottom Bar):** Pinned to the bottom using `Positioned(bottom: 0, left: 0, right: 0)`.
        -   Height increased to include `bottomSafePadding`.
        -   Added internal padding to respect the safe area for the home indicator.
    -   **Layer 4 (Slider):** Positioned above the bottom bar.
    -   **Layer 5 (Menus):** Settings and Words menus are placed on top of everything.

## Verification Results

### Code Structure Verification

-   [x] **Scaffold Body:** Confirmed it is a `Stack`.
-   [x] **Content Padding:** Confirmed `SingleChildScrollView` has correct top and bottom padding.
-   [x] **Floating Bars:** Confirmed Top and Bottom bars are `Positioned` correctly.
-   [x] **Safe Area:** Confirmed Bottom Bar handles `viewPadding.bottom` correctly.

This structure ensures that the grid content flows under the transparent/floating bars while remaining fully accessible.
