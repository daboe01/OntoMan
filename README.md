# 🧬 Human Phenotype Ontology (HPO) Browser & Phenopacket Extractor

A full-stack, desktop-class web application for navigating, searching, and inspecting the [Human Phenotype Ontology (HPO)](https://hpo.jax.org/). 

This project provides a lightning-fast native-like GUI in the browser using **Cappuccino (Objective-J)**, backed by a **PostgreSQL** database and a **Mojolicous** (Perl) backend. It efficiently parses raw `.obo` files, imports them into a relational schema, and serves them via an asynchronous, lazy-loading interface.

<img width="1195" height="907" alt="Bildschirmfoto 2026-04-13 um 10 19 35" src="https://github.com/user-attachments/assets/6cfc0ae7-4b7c-4539-a062-cad49ab77c2a" />
<img width="1015" height="1119" alt="image001" src="https://github.com/user-attachments/assets/ed4794a7-0277-45b9-b014-109edbc70de3" />


## ✨ Features

* **Desktop-Class UI:** Built with Cappuccino, providing a rich, Cocoa-like split-pane interface right in your web browser.
* **Lazy-Loading Tree View:** Navigate the massive HPO hierarchy without lag. Child nodes are fetched asynchronously only when a parent is expanded.
* **Smart Search:** Search for specific terms and the tree will automatically resolve the path, expand the necessary branches, and scroll directly to the matched node.
* **Comprehensive Metadata:** Instantly view detailed information for any selected term, including full definitions, synonyms, cross-references, and downstream nodes.
* **🤖 AI-Powered Phenopacket Extraction:** Automatically extract standard **Phenopacket v2.0** JSON objects from unstructured medical free-text. Uses LLM-based parsing and dense retrieval vector stores to map natural language directly to exact HPO IDs, resolving phenotypic features, modifiers, severity, and onset.

## 📦 Prerequisites

Before you begin, ensure you have the following installed:
* **PostgreSQL** (v10+)
* **Perl** (with `Mojolicous`, `DBI`, `DBD::Pg`, `SQL::Abstract`, and `SQL::Abstract::More` modules)
* *(Optional)* A running Vectorstore/LLM service for the Phenopacket Extractor (default expects `http://localhost:3036`).

## 🚀 Installation & Setup

### 1. Database Setup
Create a PostgreSQL database named `hpo` and run the newly added `sql_template.sql` script to set up the schema. 

From your terminal, run:

```bash
# Create the database
createdb hpo

# Import the schema from the template file
psql -d hpo -f sql_template.sql
```

*(Alternatively, if you are logged into the `psql` console, you can run `CREATE DATABASE hpo; \c hpo; \i sql_template.sql`)*

### 2. Import the OBO File
Download the latest `hp.obo` file from the [HPO Consortium](http://www.human-phenotype-ontology.org/). Update the file path in the Perl script (`import.pl`), and run it:

```bash
# Install Perl dependencies if needed
cpanm Mojolicious DBI DBD::Pg SQL::Abstract SQL::Abstract::More

# Run the importer
perl import.pl
```
*Note: The script automatically cleans the existing database before running a high-speed transactional import.*

### 3. Backend API
The frontend expects a backend serving JSON at the following endpoints (relative to `/DBB/`):

**Standard HPO Endpoints:**
* `GET /DBB/hpo/roots` - Returns the top-level HPO nodes.
* `GET /DBB/hpo/children/:id` - Returns the immediate children of a given term.
* `GET /DBB/hpo/search/:query` - Returns path arrays to nodes matching the search string (Supports both text and direct `HP:XXXXXXX` ID search).
* `GET /DBB/hpo/synonyms/:id` - Returns synonyms for a given term.
* `GET /DBB/hpo/xrefs/:id` - Returns cross-references for a given term.
* `GET /DBB/children/idparent/:id` - Returns all downstream child node metadata.

**AI Extraction Endpoints:**
* `POST /DBB/extract_phenopacket` - Accepts a JSON payload containing unstructured text and returns a mapped Phenopacket schema 2.0 object.

### 4. 🤖 Using the Phenopacket Extractor
To use the AI-powered extractor, you need to provide unstructured clinical text. The backend will asynchronously map the extracted features to HPO entities using dense retrieval. 

If your Vectorstore service runs on a different host/port, set the environment variable before starting:
```bash
export VECTORSTORE_URL="http://your-llm-backend:3036"
```

**Example Request:**
```bash
curl -X POST http://localhost:3026/DBB/extract_phenopacket \
     -H "Content-Type: application/json" \
     -d '{
           "medical_report": "The patient presented with severe seizures starting in early childhood."
         }'
```
*The response will yield a fully compliant Phenopacket v2.0 JSON including correctly formatted `HP:` IDs, onset data, and modifiers.*

### 5. Run the Backend & Frontend
Navigate to your backend project directory and start the server using `morbo` (or `hypnotoad` for production):

```bash
cd /path/to/your/backend
morbo backend.pl
```
Open your browser and navigate to the application (typically served where your frontend is configured).

## 🤝 Contributing
Contributions, issues, and feature requests are welcome!

## 📄 License
* This project is licensed under the MIT License.
* The Human Phenotype Ontology is created and maintained by the [Human Phenotype Ontology Consortium](https://hpo.jax.org/app/license).

---
*Created with ❤️ using Objective-J and Perl.*
