/**
 * Copyright (c) 2009 - 2012 Red Hat, Inc.
 *
 * This software is licensed to you under the GNU General Public License,
 * version 2 (GPLv2). There is NO WARRANTY for this software, express or
 * implied, including the implied warranties of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE. You should have received a copy of GPLv2
 * along with this software; if not, see
 * http://www.gnu.org/licenses/old-licenses/gpl-2.0.txt.
 *
 * Red Hat trademarks are not licensed under GPLv2. No permission is
 * granted to use or replicate Red Hat trademarks that are incorporated
 * in this software or its documentation.
 */
package org.candlepin.policy.js;

import java.util.Collection;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Map;
import java.util.Set;

import org.candlepin.model.Attribute;
import org.candlepin.model.Product;
import org.candlepin.model.ProductAttribute;

/**
 * Represents a read-only copy of a Product.
 */
public class ReadOnlyProduct {

    private final String productId;
    private final String productName;
    private Map<String, String> attributes;

    /**
     * read-only product constructor.
     * @param productId the product id
     * @param productName the product name.
     * @param attributes a flattened map of attribute name to value.
     */
    public ReadOnlyProduct(String productId, String productName,
        Map<String, String> attributes) {
        this.productId = productId;
        this.productName = productName;
        this.attributes = attributes;
    }

    public ReadOnlyProduct(Product product) {
        this.productId = product.getId();
        this.productName = product.getName();
        this.attributes = getFlattenedAttributes(product);
    }

    /**
     * Return the product name
     * @return the product name
     */
    public String getName() {
        return this.productName;
    }

    /**
     * Return the product id
     * @return the product id
     */
    public String getId() {
        return this.productId;
    }

    /**
     * Return product attribute matching the given name.
     * @param name attribute name
     * @return attribute value
     */
    public String getAttribute(String name) {
        return attributes.get(name);
    }

    public Map<String, String> getAttributes() {
        return attributes;
    }

    public boolean hasAttribute(String key) {
        return attributes.containsKey(key);
    }

    @Override
    public boolean equals(Object anObject) {
        if (this == anObject) {
            return true;
        }
        if (!(anObject instanceof ReadOnlyProduct)) {
            return false;
        }

        ReadOnlyProduct another = (ReadOnlyProduct) anObject;

        return this.productId.equals(another.getId());
    }

    @Override
    public int hashCode() {
        return this.productId.hashCode() * 31;
    }

    /**
     * Return a list of read-only products from the given set of products.
     * @param products read/write version of products.
     * @return read-only versions of products.
     */
    public static Set<ReadOnlyProduct> fromProducts(Collection<Product> products) {
        Set<ReadOnlyProduct> toReturn = new HashSet<ReadOnlyProduct>();
        for (Product toProxy : products) {
            toReturn.add(new ReadOnlyProduct(toProxy));
        }
        return toReturn;
    }

    private HashMap<String, String> getFlattenedAttributes(Product product) {
        HashMap<String, String> attributes = new HashMap<String, String>();
        Set<ProductAttribute> attributeList = product.getAttributes();
        if (attributeList != null) {
            for (Attribute current : attributeList) {
                attributes.put(current.getName(), current.getValue());
            }
        }
        return attributes;
    }
}
