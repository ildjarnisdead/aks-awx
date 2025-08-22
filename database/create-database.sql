CREATE DATABASE [servicename];
CREATE USER [servicename] PASSWORD '[pguserpwd]';
GRANT CONNECT ON DATABASE [servicename] TO [servicename];
GRANT ALL PRIVILEGES ON DATABASE [servicename] TO [servicename];
\c [servicename]
GRANT ALL PRIVILEGES ON SCHEMA public TO [servicename];
REVOKE ALL PRIVILEGES ON SCHEMA public FROM public;
