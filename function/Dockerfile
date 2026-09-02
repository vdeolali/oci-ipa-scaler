FROM fnproject/python:3.11-dev AS build-stage
WORKDIR /function
ADD requirements.txt /function/
RUN pip3 install --target /python --no-cache-dir -r requirements.txt
ADD . /function/
FROM fnproject/python:3.11
WORKDIR /function
COPY --from=build-stage /function /function
COPY --from=build-stage /python /python
ENV PYTHONPATH=/python
ENTRYPOINT ["/python/bin/fdk", "/function/func.py", "handler"]
