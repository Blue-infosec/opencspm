# frozen-string-literal: true

# comment
class PostLoader
  def initialize(db, import_id)
    @db = db
    @import_id = import_id
    final_steps
  end

  private

  def final_steps
    enrich_data
    install_indexes
    cleanup_data
  end

  def enrich_data
    puts 'Enriching data'
    query = """
      MATCH (np:GCP_CONTAINER_NODEPOOL)-[hsa:HAS_SERVICEACCOUNT]->(gi:GCP_IDENTITY)
      WHERE gi.name = 'serviceAccount:default'
      DETACH DELETE hsa RETURN np.name as name
    """
    container_nodepools = @db.query(query).resultset
    if container_nodepools.is_a?(Array) && !container_nodepools.empty? && container_nodepools.first.length > 0
      container_nodepools.each do |container_nodepool|
        if container_nodepool.is_a?(Array) && !container_nodepool.empty? && container_nodepool.first.length > 0
          container_nodepool = container_nodepool.first
          # Get project name from instance_template path
          gcp_compute_project = container_nodepool.split('/').slice(0 .. 2).join('/').gsub(/^container/, 'compute')
          query = """
            MATCH (np:GCP_CONTAINER_NODEPOOL { name: \"#{container_nodepool}\" }) 
            MATCH (gcp:GCP_COMPUTE_PROJECT { name: \"#{gcp_compute_project}\" })
            MATCH (gi:GCP_IDENTITY) WHERE gi.member_type = \"serviceAccount\" and gi.member_name = gcp.resource_data_defaultServiceAccount
            MERGE (np)-[:HAS_SERVICEACCOUNT]->(gi)
          """
          print '.'
          @db.query(query)
        end
      end
    end

    query = """
      MATCH (it:GCP_COMPUTE_INSTANCETEMPLATE)-[hsa:HAS_SERVICEACCOUNT]->(gi:GCP_IDENTITY)
      WHERE gi.name = 'serviceAccount:default'
      DETACH DELETE hsa RETURN it.name as name
    """
    instance_templates = @db.query(query).resultset
    if instance_templates.is_a?(Array) && !instance_templates.empty? && instance_templates.first.length > 0
      instance_templates.each do |instance_template|
        if instance_template.is_a?(Array) && !instance_template.empty? && instance_template.first.length > 0
          instance_template = instance_template.first
          # Get project name from instance_template path
          gcp_compute_project = instance_template.split('/').slice(0 .. 2).join('/')
          query = """
            MATCH (i:GCP_COMPUTE_INSTANCETEMPLATE { name: \"#{instance_template}\" }) 
            MATCH (gcp:GCP_COMPUTE_PROJECT { name: \"#{gcp_compute_project}\" })
            MATCH (gi:GCP_IDENTITY) WHERE gi.member_type = \"serviceAccount\" and gi.member_name = gcp.resource_data_defaultServiceAccount
            MERGE (i)-[:HAS_SERVICEACCOUNT]->(gi)
          """
          print '.'
          @db.query(query)
        end
      end
    end
    puts ""
  end

  def install_indexes
    puts 'Installing indexes'
    query = """
      MATCH (a) RETURN DISTINCT labels(a) as label
    """
    labels = @db.query(query).resultset
    if labels.is_a?(Array) && !labels.empty? && labels.first.length > 0
      labels.each do |label|
        if label.is_a?(Array) && !label.empty? && label.first.length > 0
          label = label.first
          query = """
            CREATE INDEX ON :#{label}(name);
            CREATE INDEX ON :#{label}(last_updated);
            CREATE INDEX ON :#{label}(loader_type);
          """
          print '.'
          @db.query(query)
        end
      end
    end
    puts ""
  end

  def cleanup_data
    puts 'Cleaning up stale resources and relationships'
    print "."
    query = """
      MATCH ()-[r]-() where r.last_updated <> #{@import_id} delete r
    """
    @db.query(query)

    print "."
    query = """
      MATCH (n) where n.last_updated <> #{@import_id} detach delete n
    """
    @db.query(query)
    puts ""
  end
end
