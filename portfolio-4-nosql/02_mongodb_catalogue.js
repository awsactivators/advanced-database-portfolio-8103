// =====================================================================
// Portfolio 4, Document model in MongoDB for the Atelier Verane product catalogue
//
// How to run (free options: MongoDB Community on your laptop, or a free Atlas M0 cluster):
//   1. mongoimport --uri "<your connection string>" --db atelier_nosql \
//        --collection products --jsonArray --file products.json --drop
//   2. mongosh "<your connection string>" --file 02_mongodb_catalogue.js
//
// Docs consulted: MongoDB Manual, Schema Validation
//   https://www.mongodb.com/docs/manual/core/schema-validation/
// Aggregation pipeline  https://www.mongodb.com/docs/manual/core/aggregation-pipeline/
// Indexes               https://www.mongodb.com/docs/manual/indexes/
// =====================================================================
const dbn = db.getSiblingDB("atelier_nosql");

// ---- 1. Flexible schema, but with guard-rails (validator keeps the core fields honest)
dbn.runCommand({
  collMod: "products",
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["_id", "name", "category", "basePrice", "variants"],
      properties: {
        basePrice: { bsonType: "number", minimum: 0 },
        category:  { enum: ["gown", "coat", "dress", "tailoring", "knitwear", "accessory"] },
        variants:  { bsonType: "array", minItems: 1,
                     items: { bsonType: "object", required: ["size", "colour", "stock"],
                              properties: { stock: { bsonType: "number", minimum: 0 } } } }
      }
    }
  },
  validationLevel: "moderate"
});

// ---- 2. Indexes that match the access patterns
dbn.products.createIndex({ category: 1, basePrice: 1 });
dbn.products.createIndex({ "collection.name": 1 });

// ---- 3. Queries that are awkward in SQL
print("--- Gowns that have a 'neckline' attribute (attribute exists only on gowns)");
printjson(dbn.products.find({ category: "gown", "attributes.neckline": { $exists: true } },
                            { name: 1, "attributes.neckline": 1 }).limit(3).toArray());

print("--- Products with any variant of size M in Noir with stock > 30");
printjson(dbn.products.find({ variants: { $elemMatch: { size: "M", colour: "Noir", stock: { $gt: 30 } } } },
                            { name: 1 }).limit(3).toArray());

// ---- 4. Adding a new attribute needs NO schema migration (slide S2_01: flexible schema)
dbn.products.updateOne({ _id: "AV-00003" }, { $set: { "attributes.sustainabilityCertified": true } });

// ---- 5. Aggregation: total stock and average price per collection
print("--- Stock and average price per collection");
printjson(dbn.products.aggregate([
  { $unwind: "$variants" },
  { $group: { _id: "$collection.name",
              totalStock: { $sum: "$variants.stock" },
              avgPrice:   { $avg: "$basePrice" } } },
  { $sort: { totalStock: -1 } }
]).toArray());

// ---- 6. Consistency dial (CAP / BASE discussion in Portfolio 5)
//  Catalogue reads can tolerate slightly stale replicas -> readPreference: "secondaryPreferred".
//  Stock decrements during checkout must not -> majority write concern on the primary.
dbn.products.updateOne(
  { _id: "AV-00001", "variants.0.stock": { $gt: 0 } },
  { $inc: { "variants.0.stock": -1 } },
  { writeConcern: { w: "majority" } }
);
