## **THE LIMITS THE CONVERSATION PAGE TELLS ITS CLIENT** (metal-vmm QUEUE
## 272): constants, said once here, where the hosted `limits!` asked the
## Zig for them each page. The Zig keeps its own copies, the ones that
## enforce them (angry-gopher chat_upload.zig `image_max`, `video_max`,
## `accept`; search_tokens.zig `min_len`), and chat_twin_test.zig holds
## them equal. Pure.
Limits := [].{

	## The largest image an upload takes: 10 MiB.
	image_max : U64
	image_max = 10 * 1024 * 1024

	## The largest video an upload takes: 100 MiB.
	video_max : U64
	video_max = 100 * 1024 * 1024

	## The accepted types, as a file picker's `accept` attribute takes them.
	accept : Str
	accept = "image/png,image/jpeg,image/gif,image/webp,video/mp4,video/webm,video/quicktime"

	## The shortest word search looks up.
	search_min : U64
	search_min = 2

	## The four, as the conversation page takes them.
	page : {
		image_max : U64,
		video_max : U64,
		accept : List(U8),
		search_min : U64,
	}
	page = {
		image_max,
		video_max,
		accept: accept.to_utf8(),
		search_min,
	}
}
