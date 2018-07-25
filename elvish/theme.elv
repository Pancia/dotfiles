use github.com/zzamboni/elvish-themes/chain
chain:bold-prompt = $true
chain:segment-style = [
	&dir=          session
	&chain=        session
	&arrow=        session
	&git-combined= session
]
edit:prompt-stale-transform = { each [x]{ styled $x[text] "gray" } }
edit:-prompt-eagerness = 10

use github.com/zzamboni/elvish-modules/terminal-title
