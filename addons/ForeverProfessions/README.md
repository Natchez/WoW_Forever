# Forever Professions (v0.1.0)

Shows which recipes use an item, and every profession across all your characters. Type `/fp` in game.

## Install
1. Exit WoW.
2. Put the `ForeverProfessions` folder in your `Interface\AddOns\` folder, so you end up with `AddOns\ForeverProfessions\ForeverProfessions.toc`.
3. Log in. If Forever Metrics is installed too, Forever Professions copies the professions, bags and trainer lists it already saw, so your other characters show up straight away. It only reads Forever Metrics' data and never changes it.

## Item tooltips, a step at a time
Items no recipe uses get nothing. For the rest:

- **Hover:** one line, like `Crafting: 2 skill-ups · 17 recipes`.
- **Hold Shift:** the top 3 recipes. Skill-ups you can make right now come first, then skill-ups you're short of materials for, then anything else you can make. Each row says which character knows it and either how many you can make, which other character has the material, or what's missing. Then a line like `+ 14 more · 1 to learn at trainer`.
- **Alt-click the item** (in your bags, the bank, or a chat link): a panel with every recipe that uses it, grouped into Skill-ups, Can make, Other recipes and Learn at trainer. Click a recipe to open it in the Recipes page.

Options > Tooltips turns each step on or off, and can leave out your other characters or grey recipes.

## The /fp window
- **Overview:** a card for each character's professions: skill, how many recipes you can craft now, what a trainer would teach you now and what it costs, and the best skill-up recipe. Tabs switch between all characters and one.
- **Recipes:** one profession at a time (`<` and `>` switch), grouped by colour. Filters: Skill-ups, Can make, Learnable, All. Search by recipe or material name. Pick a recipe to see its materials, how many you have, and which other character has what you're missing. **Link in chat** posts it.
- `/fp copper bar` opens Recipes searching for "copper bar".
- Controller: LB/RB switch character (Overview) or profession (Recipes), D-pad up/down moves, A enters, B backs out, X changes the filter. You can also bind a key or button to "Open / close Forever Professions".

## Where the data comes from
- **Recipes and their colours:** read when you open a profession window. Colours are as of that moment, so open the window again after skilling up.
- **Bags:** whenever they change. **Bank:** when you open it.
- **Trainers:** whatever a profession trainer lists when you talk to it. Forever Metrics' trainer lists are added at every login.
- **Other characters** update when you log in on them.
- **Materials of recipes you don't know** come from a recipe table built from Wowhead's Classic data (`Data.lua`, made by `tools/recipes.py`). Some Forever-only recipes aren't on Wowhead. Their materials fill in once any of your characters learns them.

## Commands
- `/fp`: open or close the window
- `/fp options`: tooltip options
- `/fp <text>`: search recipes and materials
- `/fp debug`: print errors in chat if something isn't working
