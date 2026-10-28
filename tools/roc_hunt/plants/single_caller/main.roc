## single_caller's plants: main calls FiresSolo alone (it fires), QuietShared
## with twin (quiet: twin is a caller), QuietKept (quiet: allowlisted), and
## QuietTested only inside an `expect` (quiet: a test is no caller).
import FiresSolo
import QuietShared
import QuietKept
import QuietTested

go : U64 -> U64
go = |n| FiresSolo.one(QuietShared.two(QuietKept.three(n)))

expect QuietTested.four(1) == 2
