all:

install:
	install -D -m755 wrappers/wrapper-initialize $(DESTDIR)/usr/bin/wrapper-initialize
	install -D -m755 wrappers/wrapper-pg_ctl $(DESTDIR)/usr/bin/wrapper-pg_ctl
	install -D -m755 wrappers/wrapper-psql $(DESTDIR)/usr/bin/wrapper-psql
	install -D -m755 wrappers/wrapper-foglamp $(DESTDIR)/usr/bin/wrapper-foglamp
