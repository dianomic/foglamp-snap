all:

install:
	install -D -m755 wrappers/wrapper-foglamp $(DESTDIR)/usr/bin/wrapper-foglamp
	install -D -m755 wrappers/wrapper-fogbench $(DESTDIR)/usr/bin/wrapper-fogbench
	install -D -m755 wrappers/wrapper-fogupdate $(DESTDIR)/usr/bin/wrapper-fogupdate
