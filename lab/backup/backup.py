#!/usr/bin/env python3
"""Backup lógico do lab. Só publica sucesso depois de validar bytes e retenção remotos."""
import base64
import datetime as dt
import fcntl
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import uuid

UTC = dt.timezone.utc
ROOT = Path(os.getenv('BACKUP_DIR', '/backups'))
BUCKET = os.getenv('S3_BUCKET', 'backups')


def now():
    return dt.datetime.now(UTC)


def log(event, **data):
    print(json.dumps({'time': now().isoformat(), 'event': event, **data}), flush=True)


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def client():
    # Import lazy: health e verificações locais não precisam de conexão com S3.
    import boto3
    from botocore.config import Config
    return boto3.client('s3', endpoint_url=os.environ['S3_ENDPOINT'],
                        region_name='us-east-1',
                        config=Config(signature_version='s3v4', connect_timeout=3,
                                      read_timeout=15, retries={'max_attempts': 2},
                                      s3={'addressing_style': 'path'}))


def command(args, *, outfile=None, timeout=90, env=None):
    if outfile:
        with open(outfile, 'wb') as stream:
            subprocess.run(args, check=True, stdout=stream, timeout=timeout, env=env)
    else:
        return subprocess.check_output(args, timeout=timeout, env=env, text=True).strip()


def hash_file(path, algorithm='sha256'):
    digest = hashlib.new(algorithm)
    with open(path, 'rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
    return digest


def retention(s3, key, version):
    result = s3.get_object_retention(Bucket=BUCKET, Key=key, VersionId=version)['Retention']
    require(result.get('Mode') == 'COMPLIANCE', 'Objeto sem retenção COMPLIANCE: ' + key)
    require(result['RetainUntilDate'] > now(), 'Retenção expirada: ' + key)
    return result


def put_verified(s3, path, key):
    path = Path(path)
    require(path.stat().st_size > 0, 'Arquivo vazio: ' + path.name)
    # Limite por artefato evita um upload acidental enorme neste lab pequeno.
    require(path.stat().st_size <= 256 * 1024 * 1024, 'Artefato >256 MiB: replaneje capacidade.')
    until = now() + dt.timedelta(days=int(os.getenv('RETENTION_DAYS', '7')))
    checksum = hash_file(path).hexdigest()
    with path.open('rb') as stream:
        result = s3.put_object(Bucket=BUCKET, Key=key, Body=stream,
                              ContentMD5=base64.b64encode(hash_file(path, 'md5').digest()).decode(),
                              ObjectLockMode='COMPLIANCE', ObjectLockRetainUntilDate=until)
    version = result.get('VersionId')
    require(version and version != 'null', 'Upload não retornou versão protegida.')
    lock = retention(s3, key, version)
    require(lock['RetainUntilDate'] >= until - dt.timedelta(seconds=2), 'Retenção menor que a solicitada.')
    body = s3.get_object(Bucket=BUCKET, Key=key, VersionId=version)['Body']
    digest = hashlib.sha256()
    try:
        for block in iter(lambda: body.read(1024 * 1024), b''):
            digest.update(block)
    finally:
        body.close()
    require(digest.hexdigest() == checksum, 'SHA-256 remoto divergente: ' + key)
    return {'key': key, 'version': version, 'sha256': checksum, 'bytes': path.stat().st_size}


def atomic_json(path, data):
    path = Path(path)
    tmp = path.with_suffix('.tmp')
    with tmp.open('w') as stream:
        json.dump(data, stream, indent=2)
        stream.flush()
        os.fsync(stream.fileno())
    os.replace(tmp, path)
    fd = os.open(path.parent, os.O_RDONLY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)



def verify_delete_denial(s3, meta, response):
    """Aceita bloqueio por retenção; nunca trata qualquer HTTP 400/403 como sucesso."""
    error = response.get('Error', {})
    status = response.get('ResponseMetadata', {}).get('HTTPStatusCode')
    code = str(error.get('Code', ''))
    message = str(error.get('Message', ''))
    denied = status == 403 and code == 'AccessDenied'
    minio_locked = (status == 400 and code == 'InvalidRequest'
                    and 'object is worm protected' in message.lower())
    require(denied or minio_locked,
            f'Falha inesperada ao excluir objeto de teste: HTTP {status}; {code}; {message}')
    # Após a recusa, a mesma versão precisa continuar protegida E com os mesmos bytes.
    retention(s3, meta['key'], meta['version'])
    body = s3.get_object(Bucket=BUCKET, Key=meta['key'], VersionId=meta['version'])['Body']
    digest = hashlib.sha256()
    try:
        for block in iter(lambda: body.read(1024 * 1024), b''):
            digest.update(block)
    finally:
        body.close()
    require(digest.hexdigest() == meta['sha256'],
            'Objeto de teste alterado após tentativa de exclusão.')


def init_bucket():
    from botocore.exceptions import ClientError
    s3 = client()
    # Bounded readiness wait; errors must exit nonzero, not become "TESTE OK".
    for attempt in range(30):
        try:
            s3.list_buckets()
            break
        except Exception:
            if attempt == 29:
                raise
            time.sleep(2)
    try:
        s3.head_bucket(Bucket=BUCKET)
    except ClientError as exc:
        if str(exc.response['Error']['Code']) not in ('404', 'NoSuchBucket', 'NotFound'):
            raise
        s3.create_bucket(Bucket=BUCKET, ObjectLockEnabledForBucket=True)
    cfg = s3.get_object_lock_configuration(Bucket=BUCKET)['ObjectLockConfiguration']
    require(cfg.get('ObjectLockEnabled') == 'Enabled', 'Bucket existente não tem Object Lock.')
    s3.put_object_lock_configuration(Bucket=BUCKET, ObjectLockConfiguration={
        'ObjectLockEnabled': 'Enabled', 'Rule': {'DefaultRetention': {
            'Mode': 'COMPLIANCE', 'Days': int(os.getenv('RETENTION_DAYS', '7'))}}})
    # Remoção da VERSÃO deve falhar. Delete sem VersionId só criaria delete marker.
    with tempfile.TemporaryDirectory() as folder:
        probe = Path(folder) / 'probe.txt'
        probe.write_text('prova de retenção do laboratório\n')
        meta = put_verified(s3, probe, 'probes/' + uuid.uuid4().hex + '.txt')
        try:
            s3.delete_object(Bucket=BUCKET, Key=meta['key'], VersionId=meta['version'])
        except ClientError as exc:
            verify_delete_denial(s3, meta, exc.response)
        else:
            raise RuntimeError('Imutabilidade falhou: versão COMPLIANCE foi excluída.')
    log('MINIO_LOCK_OK')


def backup_once():
    s3 = client()
    start = now()
    backup_id = start.strftime('%Y%m%dT%H%M%S.%fZ') + '-' + uuid.uuid4().hex[:8]
    # Uma sessão somente leitura não é fonte válida para o backup do escritor atual.
    require(command(['psql', '-X', '-w', '-Atq', '-v', 'ON_ERROR_STOP=1', '-c',
                     "SELECT NOT pg_is_in_recovery() AND current_setting('transaction_read_only')='off'"])
            == 't', 'Proxy não aponta para escritor válido.')
    with tempfile.TemporaryDirectory(prefix='.pending-', dir=ROOT) as folder:
        work = Path(folder)
        command(['pg_dump', '-w', '-Fc', '--lock-wait-timeout=10s', '--file', str(work / 'loja.dump')])
        command(['pg_restore', '--list', str(work / 'loja.dump')], outfile=work / 'toc.txt')
        command(['pg_dumpall', '-w', '--roles-only'], outfile=work / 'roles.sql', timeout=30)
        files = {}
        for filename in ('loja.dump', 'roles.sql'):
            files[filename] = put_verified(s3, work / filename, f'sets/{backup_id}/{filename}')
        manifest = {'id': backup_id, 'snapshot_lower_bound': start.isoformat(),
                    'uploaded_at': now().isoformat(), 'database': 'loja', 'files': files}
        atomic_json(work / 'manifest.json', manifest)
        # Manifesto publicado por último = conjunto completo.
        manifest_meta = put_verified(s3, work / 'manifest.json', f'sets/{backup_id}/manifest.json')
        dest = ROOT / 'complete' / backup_id
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copytree(work, dest)
        status = {**manifest, 'manifest_object': manifest_meta}
        atomic_json(ROOT / 'status.json', status)
        # Só conjuntos locais completos são sujeitos à retenção; nunca remove remoto.
        completed = sorted(p for p in dest.parent.iterdir() if p.is_dir())
        keep = max(1, int(os.getenv('MAX_LOCAL_KEEP', '3')))
        for old in completed[:-keep]:
            shutil.rmtree(old)
        log('BACKUP_OK', id=backup_id, snapshot=start.isoformat(),
            age_seconds=int((now() - start).total_seconds()))


def health():
    status = json.loads((ROOT / 'status.json').read_text())
    age = (now() - dt.datetime.fromisoformat(status['snapshot_lower_bound'])).total_seconds()
    require(0 <= age <= int(os.getenv('RPO_SECONDS', '300')),
            f'Último snapshot confirmado tem {age:.0f}s; fora da meta.')
    log('BACKUP_RECENTE', age_seconds=int(age), id=status['id'])


def restore_test(manifest_key=None):
    # Destino fixo proposital: nunca restaura no banco usado pela aplicação.
    s3 = client()
    if manifest_key is None:
        keys = [obj['Key'] for page in s3.get_paginator('list_objects_v2').paginate(Bucket=BUCKET, Prefix='sets/')
                for obj in page.get('Contents', []) if obj['Key'].endswith('/manifest.json')]
        require(keys, 'Nenhum conjunto remoto completo disponível.')
        manifest_key = max(keys)
    require(manifest_key.startswith('sets/') and manifest_key.endswith('/manifest.json'), 'Chave inválida.')
    response = s3.get_object(Bucket=BUCKET, Key=manifest_key)
    body = response['Body']
    try:
        manifest = json.loads(body.read())
    finally:
        body.close()
    retention(s3, manifest_key, response['VersionId'])
    with tempfile.TemporaryDirectory() as folder:
        for filename in ('loja.dump', 'roles.sql'):
            meta = manifest['files'][filename]
            require(meta['key'].startswith(manifest_key.rsplit('/', 1)[0] + '/'), 'Objeto fora do conjunto.')
            retention(s3, meta['key'], meta['version'])
            body = s3.get_object(Bucket=BUCKET, Key=meta['key'], VersionId=meta['version'])['Body']
            try:
                with open(Path(folder) / filename, 'wb') as stream:
                    shutil.copyfileobj(body, stream)
            finally:
                body.close()
            require(hash_file(Path(folder) / filename).hexdigest() == meta['sha256'], 'Dump/roles remoto corrompido.')
        env = {**os.environ, 'PGHOST': 'restore-db', 'PGPORT': '5432', 'PGUSER': 'postgres',
               'PGDATABASE': 'restorecheck', 'PGPASSWORD': 'restore-lab-only'}
        # --clean somente no destino efêmero fixo, para permitir retestes.
        command(['pg_restore', '-w', '--exit-on-error', '--clean', '--if-exists', '--no-owner',
                 '--no-privileges', '-d', 'restorecheck', str(Path(folder) / 'loja.dump')], env=env)
        count = command(['psql', '-X', '-w', '-Atq', '-v', 'ON_ERROR_STOP=1', '-c',
                         'SELECT count(*) FROM public.pedidos'], env=env)
        require(count.isdigit(), 'Tabela pedidos não foi restaurada.')
        latest = command(['psql', '-X', '-w', '-Atq', '-v', 'ON_ERROR_STOP=1', '-c',
                          "SELECT COALESCE(max(criado)::text, 'SEM PEDIDOS') FROM public.pedidos"], env=env)
        log('RESTORE_OK', manifest=manifest_key, pedidos=int(count), ultimo_pedido=latest,
            snapshot=manifest['snapshot_lower_bound'])


def main():
    os.umask(0o077)
    mode = sys.argv[1] if len(sys.argv) > 1 else 'loop'
    if mode == 'init':
        init_bucket()
    elif mode == 'health':
        health()
    elif mode == 'restore-test':
        restore_test(sys.argv[2] if len(sys.argv) > 2 else None)
    elif mode in ('once', 'loop'):
        ROOT.mkdir(parents=True, exist_ok=True)
        with (ROOT / '.backup.lock').open('w') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            # Temporários de processos interrompidos não são backups válidos.
            for stale in ROOT.glob('.pending-*'):
                if stale.is_dir():
                    shutil.rmtree(stale)
            while True:
                try:
                    backup_once()
                except Exception as exc:
                    log('BACKUP_FALHOU', error=str(exc))
                    if mode == 'once':
                        raise
                    time.sleep(15)
                    continue
                if mode == 'once':
                    break
                time.sleep(max(5, int(os.getenv('BACKUP_INTERVAL', '60'))))
    else:
        raise RuntimeError('Comando desconhecido.')


if __name__ == '__main__':
    try:
        main()
    except Exception as exc:
        log('FALHA', error=str(exc))
        sys.exit(1)
