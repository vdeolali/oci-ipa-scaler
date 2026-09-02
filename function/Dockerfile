# Supply your organization's approved FDK image locations at build time.
# No registry location is embedded in this public source file.
ARG FDK_BUILD_IMAGE=registry.example.com/fnproject/python:3.11-dev
ARG FDK_RUN_IMAGE=registry.example.com/fnproject/python:3.11

FROM ${FDK_BUILD_IMAGE} AS build-stage
WORKDIR /function
ADD requirements.txt /function/
RUN pip3 install --target /python --no-cache-dir -r requirements.txt
ADD . /function/

FROM ${FDK_RUN_IMAGE}
WORKDIR /function
COPY --from=build-stage /function /function
COPY --from=build-stage /python /python
ENV PYTHONPATH=/python
ENTRYPOINT ["/python/bin/fdk", "/function/func.py", "handler"]
