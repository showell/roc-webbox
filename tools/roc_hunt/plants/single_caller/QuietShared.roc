## A module two others call; it alone calls the builtin `Iter`, which is no
## module to move.
QuietShared := [].{
	two : U64 -> U64
	two = |n| Iter.fold(U64.to(0, n), 0, |acc, k| acc + k)
}
