NIMFLAGS = -d:release --app:console
NIM = nim

wiki2text: wiki2text.nim
	$(NIM) c $(NIMFLAGS) wiki2text.nim
