BRANCH=		$(shell hg branch)

ifeq (,$(findstring stable,$(BRANCH)))
FLAVOR=		mainline
else
FLAVOR=		stable
endif

CURRENT_VERSION_STRING=$(shell curl -fs https://version.nginx.com/nginx/$(FLAVOR))

CURRENT_VERSION=$(word 1,$(subst -, ,$(CURRENT_VERSION_STRING)))
CURRENT_RELEASE=$(word 2,$(subst -, ,$(CURRENT_VERSION_STRING)))

CURRENT_VERSION_STRING_NJS=$(shell curl -fs https://version.nginx.com/njs/$(FLAVOR))
CURRENT_VERSION_NJS=$(word 2,$(subst +, ,$(word 1,$(subst -, ,$(CURRENT_VERSION_STRING_NJS)))))
CURRENT_RELEASE_NJS=$(word 2,$(subst -, ,$(CURRENT_VERSION_STRING_NJS)))

VERSION?=	$(shell curl -fs https://hg.nginx.org/nginx/raw-file/$(BRANCH)/src/core/nginx.h | fgrep 'define NGINX_VERSION' | cut -d '"' -f 2)
RELEASE?=	1

VERSION_NJS?= $(shell curl -fs https://hg.nginx.org/njs/raw-file/default/src/njs.h | fgrep 'define NJS_VERSION' | cut -d '"' -f 2)
RELEASE_NJS?= 1

PACKAGER?=	$(shell hg config ui.username)

#TARBALL?=	https://nginx.org/download/nginx-$(VERSION).tar.gz
TARBALL?=	https://yqcu02.baidupcs.com/file/cb0579329te0b8c8143e18cf380dca9b?bkt=en-2bd419aa17f4904fa917b429d287c6d6da59b6a427ca04578ba569571e781d2109890f423fcf273a&fid=842362326-250528-397599591965727&time=1647245089&sign=FDTAXUbGERLQlBHSKfWqiu-DCb740ccc5511e5e8fedcff06b081203-Fj0z%2B1IsCysm74ej8NA90A8CyDQ%3D&to=120&size=6737920&sta_dx=6737920&sta_cs=0&sta_ft=gz&sta_ct=0&sta_mt=0&fm2=MH%2CYangquan%2CAnywhere%2C%2Cshanxi2%2Ccnc&ctime=1647244990&mtime=1647244990&resv0=-1&resv1=0&resv2=rlim&resv3=5&resv4=6737920&vuk=842362326&iv=0&htype=&randtype=&tkbind_id=0&newver=1&newfm=1&secfm=1&flow_ver=3&pkey=en-461f94f3e735718dc109e2a426f22754687e41127a180b3247506006adfa4ccc53ca6d509416919d&sl=76480590&expires=8h&rt=sh&r=860578777&vbdid=522150134&fin=nginx-1.20.2.tar.gz&fn=nginx-1.20.2.tar.gz&rtype=1&dp-logid=532501363704908821&dp-callid=0.1&hps=1&tsl=80&csl=80&fsl=-1&csign=KFsxfr4duudVbBcg0VdLJJ6yqIU%3D&so=0&ut=6&uter=4&serv=0&uc=3622509817&ti=068bcab50ae430c7a1737ff9c3608309b0940ddeda3fbd94&hflag=30&from_type=1&adg=c_06510589a455673d226016b44e302c13&reqlabel=250528_f_4c61cf9689e9ece28f8af5858fb07f80_-1_c9f5e4bca60f91da78454c7e4994d035&by=themis&resvsflag=1-0-0-1-1-1

TARBALL_NJS?=	https://hg.nginx.org/njs/archive/$(VERSION_NJS).tar.gz

BASE_MAKEFILES=	alpine/Makefile \
		debian/Makefile \
		rpm/SPECS/Makefile

MODULES=	geoip image-filter perl xslt
EXTERNAL_MODULES=	auth-spnego brotli encrypted-session fips-check geoip2 headers-more lua modsecurity ndk njs opentracing passenger rtmp set-misc subs-filter

ifeq ($(shell sha512sum --version >/dev/null 2>&1 || echo FAIL),)
SHA512SUM = sha512sum
else ifeq ($(shell shasum --version >/dev/null 2>&1 || echo FAIL),)
SHA512SUM = shasum -a 512
else ifeq ($(shell openssl version >/dev/null 2>&1 || echo FAIL),)
SHA512SUM = openssl dgst -r -sha512
else
SHA512SUM = $(error SHA-512 checksumming not found)
endif

default:
	@{ \
		echo "Latest available $(FLAVOR) nginx package version: $(CURRENT_VERSION)-$(CURRENT_RELEASE)" ; \
		echo "Next $(FLAVOR) release version: $(VERSION)-$(RELEASE)" ; \
		echo "Latest available $(FLAVOR) njs package version: $(CURRENT_VERSION_NJS)-$(CURRENT_RELEASE_NJS)" ; \
		echo "Next njs version: $(VERSION_NJS)" ; \
		echo ; \
		echo "Valid targets: release release-njs revert commit tag" ; \
	}

version-check:
	@{ \
		if [ "$(VERSION)-$(RELEASE)" = "$(CURRENT_VERSION)-$(CURRENT_RELEASE)" ]; then \
			echo "Version $(VERSION)-$(RELEASE) is the latest one, nothing to do." >&2 ; \
			exit 1 ; \
		fi ; \
	}

version-check-njs:
	@{ \
		if [ "$(VERSION_NJS)-$(RELEASE_NJS)" = "$(CURRENT_VERSION_NJS)-$(CURRENT_RELEASE_NJS)" ]; then \
			echo "Version $(VERSION_NJS)-$(RELEASE_NJS) is the latest one, nothing to do." >&2 ; \
			exit 1 ; \
		fi ; \
	}

nginx-$(VERSION).tar.gz:
	curl -o nginx-$(VERSION).tar.gz -fL $(TARBALL)

njs-$(VERSION_NJS).tar.gz:
	curl -o njs-$(VERSION_NJS).tar.gz -fL $(TARBALL_NJS)

release: version-check nginx-$(VERSION).tar.gz
	@{ \
		set -e ; \
		echo "==> Preparing $(FLAVOR) release $(VERSION)-$(RELEASE)" ; \
		$(SHA512SUM) nginx-$(VERSION).tar.gz >>contrib/src/nginx/SHA512SUMS ; \
		sed -e "s,^NGINX_VERSION :=.*,NGINX_VERSION := $(VERSION),g" -i contrib/src/nginx/version ; \
		for f in $(BASE_MAKEFILES); do \
			echo "--> $${f}" ; \
			sed -e "s,^BASE_RELEASE=.*,BASE_RELEASE=	$(RELEASE),g" \
				-i $${f} ; \
		done ; \
		reldate=`date +"%Y-%m-%d"` ; \
		reltime=`date +"%H:%M:%S %z"` ; \
		packager=`echo "$(PACKAGER)" | sed -e 's,<,\\\\\\&lt\;,' -e 's,>,\\\\\\&gt\;,'` ; \
		CHANGESADD="\n\n\n<changes apply=\"nginx\" ver=\"$(VERSION)\" rev=\"$(RELEASE)\"\n         date=\"$${reldate}\" time=\"$${reltime}\"\n         packager=\"$${packager}\">\n<change>\n<para>\n$(VERSION)-$(RELEASE)\n</para>\n</change>\n\n</changes>" ; \
		sed -i -e "s,title=\"nginx\">,title=\"nginx\">$${CHANGESADD}," docs/nginx.xml ; \
		for module in $(MODULES); do \
			echo "--> changelog for nginx-module-$${module}" ; \
			module_underscore=`echo $${module} | tr '-' '_'` ; \
			CHANGESADD="\n\n\n<changes apply=\"nginx-module-$${module}\" ver=\"$(VERSION)\" rev=\"$(RELEASE)\"\n         date=\"$${reldate}\" time=\"$${reltime}\"\n         packager=\"$${packager}\">\n<change>\n<para>\nbase version updated to $(VERSION)-$(RELEASE)\n</para>\n</change>\n\n</changes>" ; \
			sed -i -e "s,title=\"nginx_module_$${module_underscore}\">,title=\"nginx_module_$${module_underscore}\">$${CHANGESADD}," docs/nginx-module-$${module}.xml ; \
		done ; \
		for module in $(EXTERNAL_MODULES); do \
			echo "--> changelog for nginx-module-$${module}" ; \
			module_version=`fgrep apply docs/nginx-module-$${module}.xml | head -1 | cut -d '"' -f 4` ; \
			module_underscore=`echo $${module} | tr '-' '_'` ; \
			CHANGESADD="\n\n\n<changes apply=\"nginx-module-$${module}\" ver=\"$${module_version}\" rev=\"$(RELEASE)\" basever=\"$(VERSION)\"\n         date=\"$${reldate}\" time=\"$${reltime}\"\n         packager=\"$${packager}\">\n<change>\n<para>\nbase version updated to $(VERSION)-$(RELEASE)\n</para>\n</change>\n\n</changes>" ; \
			sed -i -e "s,title=\"nginx_module_$${module_underscore}\">,title=\"nginx_module_$${module_underscore}\">$${CHANGESADD}," docs/nginx-module-$${module}.xml ; \
		done ; \
		echo ; \
		echo "Done. Please carefully check the diff. Use \"make revert\" to revert any changes." ; \
		echo ; \
	}

release-njs: version-check-njs njs-$(VERSION_NJS).tar.gz
	@{ \
		set -e ; \
		echo "==> Preparing $(FLAVOR) njs release $(VERSION_NJS)-$(RELEASE_NJS)" ; \
		$(SHA512SUM) njs-$(VERSION_NJS).tar.gz > contrib/src/njs/SHA512SUMS ; \
		sed -e "s,^NJS_VERSION :=.*,NJS_VERSION := $(VERSION_NJS),g" -i contrib/src/njs/version ; \
		reldate=`date +"%Y-%m-%d"` ; \
		reltime=`date +"%H:%M:%S %z"` ; \
		packager=`echo "$(PACKAGER)" | sed -e 's,<,\\\\\\&lt\;,' -e 's,>,\\\\\\&gt\;,'` ; \
		echo "--> changelog for nginx-module-njs" ; \
		CHANGESADD="\n\n\n<changes apply=\"nginx-module-njs\" ver=\"$(VERSION_NJS)\" rev=\"$(RELEASE_NJS)\" basever=\"$(CURRENT_VERSION)\"\n         date=\"$${reldate}\" time=\"$${reltime}\"\n         packager=\"$${packager}\">\n<change>\n<para>\nnjs updated to $(VERSION_NJS)\n</para>\n</change>\n\n</changes>" ; \
		sed -i -e "s,title=\"nginx_module_njs\">,title=\"nginx_module_njs\">$${CHANGESADD}," docs/nginx-module-njs.xml ; \
		echo ; \
		echo "Done. Please carefully check the diff. Use \"make revert\" to revert any changes." ; \
		echo ; \
	}

revert:
	@hg revert -v contrib/src/nginx/ docs/ $(BASE_MAKEFILES) contrib/src/njs/

commit:
	@hg commit -vm 'Updated nginx to $(VERSION)'

tag:
	@hg tag -v $(VERSION)-$(RELEASE)

.PHONY: version-check version-check-njs release release-njs revert commit tag
