## **THE CHAT'S ONE WAY TO THE DISK**: every file primitive the chat calls
## is called here, on a path Paths.roc made (tools/roc_hunt's `fs_bypass`
## flags a call anywhere else).
import pf.Host
import Paths

Files := [].{

	## Host.read!'s answer as one tag: the file's bytes, nothing there, or a
	## read that failed (the request has failed: what follows writes nothing).
	read! : Paths.ChatPath => [Found(List(U8)), Missing, Failed]
	read! = |path| {
		got = Host.read!(Paths.bytes(path))
		match got.status {
			Found => Found(got.bytes)
			Missing => Missing
			Failed => Failed
		}
	}
}
