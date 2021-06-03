FROM registry.fedoraproject.org/fedora:34

RUN dnf update -y \
	&& dnf install -y \
		ShellCheck \
		make \
	&& dnf clean all

WORKDIR /src

COPY ./ ./
