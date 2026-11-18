# Forever Professions (v0.1.6)

Shows which recipes use an item, and every profession across all your characters. Type `/fp` in game.

## Install
1. Exit WoW.
2. Put the `ForeverProfessions` folder in your `Interface\AddOns\` folder, so you end up with `AddOns\ForeverProfessions\ForeverProfessions.toc`.
3. Log in. If Forever Metrics is installed too, Forever Professions copies the professions, bags and trainer lists it already saw, so your other characters show up straight away. It only reads Forever Metrics' data and never changes it.

## Item tooltips, a step at a time
Items no recipe uses get nothing. For the rest:

- **Hover:** who has it, like `On hand: Gene 41 · Ollie 12 · Bobb 3 (56)` (this character first, bags and bank together), then `Crafting: 2 skill-ups · 17 recipes`. "On hand" shows on crafting materials and anything a recipe uses, not on gear.
- **Hold Shift:** each character's count split into bags and bank, then the top 3 recipes, each with its icon. Skill-ups you can make right now come first, then skill-ups you're short of materials for, then anything else you can make. Each row says which character knows it and either how many you can make, which other character has the material, or what's missing. Then a line like `+ 14 more · 1 to learn at trainer`.
- **Alt-click the item** (in your bags, the bank, or a chat link): a panel with every recipe that uses it, grouped into Skill-ups, Can make, Other recipes and Learn at trainer. Click a recipe to open it in the Recipes page.

Options > Tooltips turns each step on or off, and can leave out your other characters or grey recipes.

## The /fp window
- **Overview:** a card for each character's professions: skill, how many recipes you can craft now, what a trainer would teach you now and what it costs, and the best skill-up recipe. Tabs switch between all characters and one.
- **Recipes:** one profession at a time (`<` and `>` switch), grouped by colour. Filters: Skill-ups, Can make, Learnable, All. Search by recipe or material name. Pick a recipe to see its materials, how many you have, and which other character has what you're missing. **Link in chat** posts it.
- `/fp copper bar` opens Recipes searching for "copper bar".
- A **/fp** button sits just outside the right edge of your profession window and opens Recipes on that profession (turn it off under Options > Tooltips).
- Controller: LB/RB switch character (Overview) or profession (Recipes), D-pad up/down moves, A enters, B backs out, X changes the filter. You can also bind a key or button to "Open / close Forever Professions".

## Auction house prices (new in v0.1.6)
- **Getting prices:** at the auction house, click **Price materials** (just outside the right edge of the AH window). It looks up, one at a time, every material your characters' recipes use and every item they make. Click it again to stop. Anything you browse or search at the AH is also recorded as you go.
- **What's kept:** the lowest buyout per item, saved per realm and faction and shared by all your characters. Prices are only as fresh as your last look, and tooltips say how old they are.
- **Tooltips:** `AH: 12s 50c each · 2h ago` on hover; Shift adds what a stack is worth.
- **Recipes page:** each material's cost, then `Materials 12s · Sells for 20s · Profit 8s` (or Loss). Materials with no listings are counted as "not priced", so the total can be low. Vendor-bought materials (Weak Flux, thread) only show an AH price if someone lists them.
- Options > Tooltips > "Show auction house prices" turns the tooltip line off.

## Where the data comes from
- **Recipes and their colours:** read when you open a profession window. Colours are as of that moment, so open the window again after skilling up.
- **Training (from v0.1.3):** recipes you buy at a trainer count as known right away, and Journeyman, Expert and Artisan raise your skill cap right away, no reload or window needed. A just-learned recipe is listed in white under "Just learned" until you open the profession window, which gives its colour. Skill-ups update from the chat message.
- **Bags** (including the reagent bag): whenever they change. **Bank:** when you open it.
- **Trainers:** whatever a profession trainer lists when you talk to it. Forever Metrics reads the full list (every filter); Forever Professions adds what it found while you're still at the trainer, and again when you close it.
- **Other characters** update when you log in on them.
- **Materials of recipes you don't know** come from a recipe table built from Wowhead's Classic data (`Data.lua`, made by `tools/recipes.py`). Some Forever-only recipes aren't on Wowhead. Their materials fill in once any of your characters learns them.

## Commands
- `/fp`: open or close the window
- `/fp options`: tooltip options
- `/fp <text>`: search recipes and materials
- `/fp debug`: print errors in chat if something isn't working
