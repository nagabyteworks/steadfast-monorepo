# Stop-Loss, Target, and Trailing Behavior

This document describes how the initial stop-loss (SL) and target work, and how optional trailing SL and target trailing change during an open position.

## Terms

- **Entry price**: The price at which the position is opened.
- **LTP**: Last traded price, used to determine whether an SL or target level has been reached.
- **Points**: Absolute price differences, not percentages. For example, 5 points above 100 is 105.
- **Milestone**: A target price that, when reached with target trailing enabled, advances the SL and the next target level.

## Initial SL and target

The SL limits the loss if the price moves against the position. The target defines the initial favorable price level.

For a **BUY** position:

- Initial SL = entry price - SL points.
- Initial target = entry price + target points.

For a **SELL** position:

- Initial SL = entry price + SL points.
- Initial target = entry price - target points.

Example for a BUY entered at 100 with an SL distance of 10 points and a target distance of 20 points:

- Initial SL: 90.
- Initial target: 120.

The SL and target are configured independently. Reaching the SL exits the position. Manual exit is also available at any time. When target trailing is disabled, target handling remains the normal, non-trailing behavior.

## Trailing SL

Trailing SL is optional and has its own enable toggle and trailing-distance input in points. When enabled, the stop follows the market only as it moves in the position's favor; it never moves backward and increases the risk.

- For a BUY, track the highest LTP since entry. The trailing SL candidate is `highest LTP - trailing distance`. The active SL is the higher of this candidate and the current SL.
- For a SELL, track the lowest LTP since entry. The trailing SL candidate is `lowest LTP + trailing distance`. The active SL is the lower of this candidate and the current SL.

For example, for a BUY with an initial SL of 90 and a trailing distance of 5 points, if the highest LTP reaches 110, the trailing SL candidate is 105. If the price then falls, the SL stays at 105; it does not follow the price down.

The trailing SL input is a distance from the most favorable LTP, not a step size. The SL exits the position when the applicable SL level is reached.

## Target trailing

Target trailing is optional and has its own enable toggle and trailing-step input in points. It advances the target in fixed increments when each target milestone is reached.

When enabled:

1. Keep the position open when LTP reaches a target milestone; a milestone is not an exit instruction.
2. Move the SL to the milestone just reached.
3. Advance the target by the configured trailing step, in the favorable direction.
4. Repeat for each subsequent milestone. Continue until the SL is hit or the user manually exits.

For a BUY, each new target is above the previous one. For a SELL, each new target is below the previous one. Reaching a milestone only advances the SL and target; it does not close the position.

Example for a BUY entered at 100:

- Initial SL: 90.
- Initial target: 120.
- Target trailing step: 5 points.
- When LTP reaches 120, keep the position open, move the SL to 120, and set the next target to 125. The following target milestone is 130.
- When LTP reaches 125, move the SL to 125 and set the next target to 130. Continue in 5-point increments.

For a SELL, apply the same rule in reverse: each reached milestone moves the SL down to that milestone and places the next target 5 points lower.

The target trailing input is the increment between successive target milestones. It is separate from the trailing SL distance. If target trailing is disabled, this milestone-based SL advancement does not occur.
