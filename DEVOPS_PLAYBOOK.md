# 🛠️ دليل ومرجع الـ DevOps للنشر والسحب (DevOps Deployment & Pull Playbook)
### خاص بمهندسي البنية التحتية والـ DevOps — منصة بوابة قيادتي (Qyadati APISIX)

---

## 📌 1. فلسفة الفصل بين المطور والـ DevOps (Separation of Concerns)

> [!NOTE]
> **دور المطور (Developer):**
> * كتابة وتعريف الـ Routes والـ Services والـ Plugins.
> * توفير ملفات الإعدادات لكل البيئات (`configs/flavors/`).
> * عمل `git push` بعد الاختبار المحلي فقط.
> 
> **دور الـ DevOps (Your Role):**
> * التحكم الكامل في **طريقة ومكان الـ Pull والـ Deploy**.
> * اختيار الـ Flavor المناسب لكل سيرفر / بيئة.
> * حقن الـ Secrets، الـ IPs، الـ Domains، وشهادات الـ SSL.
> * تطبيق استراتيجيات الـ Deployment (GitOps, CI/CD, ArgoCD, Ansible, أو Manual Pull).

---

## 📂 2. خريطة مسارات الـ Flavors الجاهزة في المستودع

المطور يرفع لك كل الحالات مسبقاً داخل مجلد `configs/flavors/`:

```text
configs/flavors/
├── desktop/apisix.yaml  # 💻 بيئة الأجهزة الشخصية للمطورين (Local Mock)
├── local/apisix.yaml    # 🏢 سيرفر محلي داخل شبكة الشركة (On-Premise LAN)
├── dev/apisix.yaml      # 🛠️ سيرفر التطوير السحابي المشترك (Dev Server)
├── staging/apisix.yaml  # 🧪 سيرفر الاختبارات و QA / UAT
└── prod/apisix.yaml     # 🚀 سيرفر الإنتاج الفعلي (AWS / Bare-Metal)
```

---

## 🚀 3. طرق سحب ونشر الإعدادات المتاحة للـ DevOps (Deployment Strategies)

يمكنك كمهندس DevOps اختيار أي طريقة تناسب بنيتك التحتية وسيرفراتك:

### 🅰️ الطريقة 1: النشر التلقائي عبر CI/CD (GitHub Actions)
إذا كانت السيرفرات السحابية تستقبل طلبات من GitHub Actions:
1. قم بضبط الـ **GitHub Secrets** التالية في المستودع:
   * `DEV_APISIX_ADMIN_URL` & `DEV_APISIX_ADMIN_TOKEN`
   * `STAGING_APISIX_ADMIN_URL` & `STAGING_APISIX_ADMIN_TOKEN`
   * `PROD_APISIX_ADMIN_URL` & `PROD_APISIX_ADMIN_TOKEN`
2. بمجرد عمل `Merge` في `main` أو رفع `Tag`، الـ Pipeline سيقوم بسحب الـ Flavor المطلوب وضخه للـ Admin API مباشرة بتقنية **Zero-Downtime Hot Reload**.

---

### 🅱️ الطريقة 2: السحب المباشر على السيرفر (Server-Side Pull & Sync)
لو السيرفر داخل شبكة مغلقة (Private VPC / On-Premise) ولا يمكن الوصول له من الخارج:

1. **ادخل على السيرفر المستهدف:**
   ```bash
   cd /opt/qyadati/apisix
   git pull origin main
   ```

2. **نفذ المزامنة للـ Flavor الخاص بهذا السيرفر:**
   ```bash
   # لسيرفر الإنتاج (Production):
   adc sync -f configs/flavors/prod/apisix.yaml \
            --apisix-admin-url http://127.0.0.1:9181 \
            --apisix-admin-token $ADMIN_TOKEN

   # لسيرفر الـ Staging:
   adc sync -f configs/flavors/staging/apisix.yaml \
            --apisix-admin-url http://127.0.0.1:9181 \
            --apisix-admin-token $ADMIN_TOKEN

   # أو عبر السكريبت الجاهز:
   ./scripts/sync.sh prod
   ```

---

### 🅲 الطريقة 3: الجدولة أو الـ Webhook (Automated Pull Agent)
يمكنك وضع Cron Job أو Webhook Listener على السيرفر للسحب الدوري أو عند تلقي إشعار:

```bash
# مثال Cron Job كل 5 دقائق للسحب والمزامنة الآلية
*/5 * * * * cd /opt/qyadati/apisix && git pull && ./scripts/sync.sh prod > /var/log/apisix-sync.log 2>&1
```

---

## ⚙️ 4. تخصيص وتعديل البنية التحتية (DevOps Overrides)

لو أردت تعديل أو إضافة أي شيء خاص بالبنية التحتية دون التأثير على كود المطورين:

### 1. تخصيص ملف الـ `.env`
انسخ `.env.example` إلى `.env` وعدل الـ Ports، الـ Passwords، أو أسماء الـ Containers:
```bash
cp .env.example .env
```

### 2. تخصيص `docker-compose.override.yml` (اختياري)
إذا أردت ربط شبكات مخصصة (Custom Networks)، أو تركيب Volumes خاصة بالسيرفر:
```yaml
# docker-compose.override.yml
version: '3.8'
services:
  apisix:
    networks:
      - production-vpc-network
    extra_hosts:
      - "auth-service.internal:10.0.2.15"

networks:
  production-vpc-network:
    external: true
```

---

## 🩺 5. أوامر الفحص والتحقق السريع (DevOps Healthcheck)

```bash
# 1. التحقق من صحة ملف الـ YAML قبل تطبيقه (Dry Run)
adc validate -f configs/flavors/prod/apisix.yaml

# 2. مقارنة الاختلافات بين الملف والسيرفر الحي (Diff)
adc diff -f configs/flavors/prod/apisix.yaml

# 3. اختبار استجابة البوابة
curl -i http://localhost:9280/health
```
