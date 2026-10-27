## Plants for `fs_bypass`: parsed, never compiled.
Plants := [].{
	fires_read : List(U8) => List(U8)
	fires_read = |path| Host.read!(path).bytes

	fires_write : List(U8) => Bool
	fires_write = |path| Host.write!(path, [])

	fires_append : List(U8) => Bool
	fires_append = |path| if Host.append_line!(path, []) Host.remove!(path) else Bool.False

	fires_entry : List(U8) => List(U8)
	fires_entry = |path| Host.append_entry!(path, [], []).bytes

	fires_list : List(U8) => List(U8)
	fires_list = |path| Host.list!(path).bytes

	quiet_files : Paths.ChatPath => [Found(List(U8)), Missing, Failed]
	quiet_files = |path| Files.read!(path)

	quiet_table : { read! : List(U8) => List(U8) }
	quiet_table = { read!: Host.read! }

	quiet_me : {} => List(U8)
	quiet_me = |_| Host.me!({})
}
