-- Esquema inicial da Loja Potengi (cliente fictício do Módulo 9.1)
CREATE USER replicador WITH REPLICATION LOGIN PASSWORD 'replica123';

CREATE TABLE pedidos (
  id      bigserial     PRIMARY KEY,
  cliente text          NOT NULL,
  valor   numeric(10,2) NOT NULL,
  criado  timestamptz   NOT NULL DEFAULT now()
);

CREATE INDEX idx_pedidos_criado ON pedidos (criado);
