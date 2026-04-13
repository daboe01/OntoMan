# 🧬 Human Phenotype Ontology (HPO) Browser

A full-stack, desktop-class web application for navigating, searching, and inspecting the [Human Phenotype Ontology (HPO)](https://hpo.jax.org/). 

This project provides a lightning-fast native-like GUI in the browser using **Cappuccino (Objective-J)**, backed by a **PostgreSQL** database and a **Perl** backend. It efficiently parses raw `.obo` files, imports them into a relational schema, and serves them via an asynchronous, lazy-loading interface.

![Screenshot Placeholder](https://via.placeholder.com/800x450.png?text=Add+a+Screenshot+of+your+Cappuccino+App+Here)

## ✨ Features

* **Desktop-Class UI:** Built with Cappuccino, providing a rich, Cocoa-like split-pane interface right in your web browser.
* **Lazy-Loading Tree View:** Navigate the massive HPO hierarchy without lag. Child nodes are fetched asynchronously only when a parent is expanded.
* **Smart Search:** Search for specific terms and the tree will automatically resolve the path, expand the necessary branches, and scroll directly to the matched node.
* **Comprehensive Metadata:** Instantly view detailed information for any selected term, including:
  * Full Definitions
  * Synonyms
  * Cross-References (Xrefs - e.g., UMLS, SNOMED)
  * Downstream/Child Nodes
* **High-Performance Parser:** A custom Perl script utilizing transactions to rapidly parse massive `.obo` files and populate the relational database.

## 🛠️ Tech Stack

* **Frontend:**[Cappuccino](http://www.cappuccino.dev/) (Objective-J)
* **Database:** PostgreSQL
* **Data Ingestion:** Perl (`DBI`, `SQL::Abstract`, `Mojo::File`)
* **API Backend:**  Mojolicious serving endpoints to `/DBB/...`

## 📦 Prerequisites

Before you begin, ensure you have the following installed:
* **PostgreSQL** (v10+)
* **Perl** (with `Mojolicous`, `DBI`, `DBD::Pg`, and `SQL::Abstract` modules)
* **Cappuccino** 

## 🚀 Installation & Setup

### 1. Database Setup
Create a PostgreSQL database named `hpo` and run the following SQL script to set up the schema:

```sql
CREATE DATABASE hpo;
\c hpo;

CREATE TABLE terms (
    id VARCHAR(20) PRIMARY KEY,
    label TEXT,
    definition TEXT,
    comment TEXT
);

CREATE TABLE synonyms (
    idterm VARCHAR(20) REFERENCES terms(id) ON DELETE CASCADE,
    label TEXT
);

CREATE TABLE xrefs (
    idterm VARCHAR(20) REFERENCES terms(id) ON DELETE CASCADE,
    label TEXT
);

CREATE TABLE isas (
    idchild VARCHAR(20) REFERENCES terms(id) ON DELETE CASCADE,
    idparent VARCHAR(20) REFERENCES terms(id) ON DELETE CASCADE
);
```

### 2. Import the OBO File
Download the latest `hp.obo` file from the[HPO Consortium](http://www.human-phenotype-ontology.org/). Update the file path in the Perl script (`import.pl`), and run it:

```bash
# Install Perl dependencies if needed
cpanm Mojolicious DBI DBD::Pg SQL::Abstract

# Run the importer
perl import.pl
```
*Note: The script automatically cleans the existing database before running a high-speed transactional import.*

### 3. Backend API
The frontend expects a backend serving JSON at the following endpoints (relative to `/DBB/`):
* `GET /DBB/hpo/roots` - Returns the top-level HPO nodes.
* `GET /DBB/hpo/children/:id` - Returns the immediate children of a given term.
* `GET /DBB/hpo/search/:query` - Returns path arrays to nodes matching the search string.
* `GET /DBB/hpo/synonyms/:id` - Returns synonyms for a given term.
* `GET /DBB/hpo/xrefs/:id` - Returns cross-references for a given term.
* `GET /DBB/children/idparent/:id` - Returns all downstream child node metadata.

### 4. Build and Run the Frontend
Navigate to your Cappuccino project directory and run:

```bash
cd /path/to/your/backend
morbo backend.pl
```
Open your browser and navigate to `http://localhost:3000`.

## 🤝 Contributing
Contributions, issues, and feature requests are welcome! Feel free to check the [issues page](link-to-issues).

## 📄 License
* This project is licensed under the MIT License.
* The Human Phenotype Ontology is created and maintained by the [Human Phenotype Ontology Consortium](https://hpo.jax.org/app/license).

---
*Created with ❤️ using Objective-J and Perl.*
