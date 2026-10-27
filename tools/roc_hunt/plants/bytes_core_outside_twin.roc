## Plants for `bytes_core_outside_twin`: parsed, never compiled.
Plants := [].{
	fires_url : List(U8), List(U8) -> List(U8)
	fires_url = |key, topic| Fanout.topic_url_bytes({ key, topic })

	fires_transcript : List(U8), List(U8) -> List(U8)
	fires_transcript = |dir, topic| Paths.transcript_path_bytes(dir, topic)

	quiet_typed : Paths.TopicAt -> List(U8)
	quiet_typed = |at| Fanout.topic_url(at)

	quiet_unwrap : Paths.ConvKey -> List(U8)
	quiet_unwrap = |key| Paths.conv_key_bytes(key)

	quiet_uid : List(U8) -> Uid
	quiet_uid = |b| Uid.from_bytes(b)

	quiet_own_module : List(U8), List(U8) -> List(U8)
	quiet_own_module = |key, topic| topic_url_bytes({ key, topic })
}
