- # TIL
- `cat` to view what is pressed
- zsh loading order:
  | file     | Interactive Login | Interactive Not Login | Script |
  |----------|-------------------|-----------------------|--------|
  | zshenv   | il | inl                   | s      |
  |----------|-------------------|-----------------------|--------|
  | zprofile | il                |                       |        |
  |----------|-------------------|-----------------------|--------|
  | zshrc    | il                | inl                   |        |
  |----------|-------------------|-----------------------|--------|
  | zlogin   | il                |                       |        |
  |----------|-------------------|-----------------------|--------|
  | zlogout  | il                |                       |        |
	- eg: if its a script, it'll only load zshenv