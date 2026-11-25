i want to have sl and target startgy, lets call it target trailing. show an input with toggle like sl and target for target trailing input. when it is enabled, the points given should be used to trail the target. 


for example:

Example: BUY position
Assume:
- Entry price: ₹100
- Initial SL: 10 points - ₹90
- target: 20 points -> ₹120 price
- target trail: 5 points from target ->

if ltp(last traded price) reachs the target 120, move the sl to 120 and set new target to 125 and target trail to 130
Price reaches the next milestone
Move SL forward to the newly achieved milestone.
Continue trailing

Repeat indefinitely until SL is hit or user manually exit.
Important: Reaching a target milestone does not close the position. It only advances the stop-loss.

ask me if you have any doubts.