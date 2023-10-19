


FROM public.ecr.aws/docker/library/node:18-alpine as builder

RUN apk add git python3 make gcc

WORKDIR /usr/src/app

COPY package.json ./

RUN npm install

# Bundle app source
COPY . /usr/src/app/


RUN npm run build

FROM public.ecr.aws/nginx/nginx:stable-alpine

ARG ENABLE_HTACCESS=false

COPY ./nginx/nginx.conf /etc/nginx/nginx.conf
COPY ./nginx/default.conf /etc/nginx/conf.d/default.conf
COPY ./nginx/.htpasswd /etc/nginx/conf.d/.htpasswd

# RUN sed -ri -e "s!chunk-vendors.2.js!chunk-vendors.latest.js!g" /etc/nginx/conf.d/default.conf


RUN if [ "$ENABLE_HTACCESS" = "true" ] ; then sed -ri -e "s!#auth!auth!g" /etc/nginx/conf.d/default.conf ; fi


COPY --from=builder /usr/src/app/out /usr/share/nginx/html
