module ActiveTriples
  ##
  # Persistence strategy for projecting `RDFSource`s onto the graph of an owning
  # parent source. This allows individual resources to be treated as within the
  # scope of another `RDFSource`.
  class ParentStrategy
    include PersistenceStrategy

    # @!attribute [r] obj
    #   the source to persist with this strategy
    # @!attribute [r] parent
    #   the target parent source for persistence
    attr_reader :obj, :parent

    ##
    # @param obj [RDFSource, RDF::Enumerable] the `RDFSource` (or other
    #   `RDF::Enumerable` to persist with the strategy.
    def initialize(obj)
      @obj = obj
    end

    def persisted?
      super && parent.persisted?
    end

    def destroy
      super { parent.destroy_child(obj) }
    end

    # Clear out any old assertions in the repository about this node or statement
    # thus preparing to receive the updated assertions.
    def erase_old_resource
      if obj.rdf_subject.node?
        final_parent.statements.each do |statement|
          final_parent.send(:delete_statement, statement) if
            statement.subject == obj.rdf_subject
        end
      else
        final_parent.delete [obj.rdf_subject, nil, nil]
      end
    end

    ##
    # @return [Enumerator<RDFSource>]
    def ancestors
      Ancestors.new(obj).to_enum
    end

    ##
    # @return [#persist!] the last parent in a chain from `parent` (e.g.
    #   the parent's parent's parent). This is the RDF::Mutable that the
    #   object will project itself on when persisting.
    def final_parent
      ancestors.to_a.last
    end

    ##
    # Sets the target "parent" source for persistence operations.
    #
    # @param parent [RDFSource] source with a persistence strategy,
    #   must be mutable.
    def parent=(parent)
      raise UnmutableParentError unless parent.is_a? RDF::Mutable
      raise UnmutableParentError unless parent.mutable?
      @parent = parent
    end

    ##
    # Persists the object to the final parent.
    #
    # @return [true] true if the save did not error
    def persist!
      erase_old_resource
      final_parent << obj
      @persisted = true
    end

    ##
    # Repopulates the graph from parent.
    #
    # @return [Boolean]
    def reload
      obj << final_parent.query(subject: obj.rdf_subject)
      @persisted = true unless obj.empty?
      true
    end

    ##
    # An enumerable over the ancestors of an object
    class Ancestors
      include Enumerable

      # @!attribute obj
      #   @return [RDFSource]
      attr_reader :obj

      ##
      # @param obj [RDFSource]
      def initialize(obj)
        @obj = obj
      end
      
      ##
      # @yield [RDFSource] gives each ancestor to the block
      # @return [Enumerator<RDFSource>]
      #
      # @raise [NilParentError] if `obj` does not persist to a parent
      def each
        raise NilParentError if 
          !obj.persistence_strategy.respond_to?(:parent) || 
          obj.persistence_strategy.parent.nil?
        
        current = obj.persistence_strategy.parent
        
        if block_given?
          loop do
            yield current
            
            break unless (current.persistence_strategy.respond_to?(:parent) && 
                          current.persistence_strategy.parent)
            break if current.persistence_strategy.parent == current

            current = current.persistence_strategy.parent
          end
        end
        to_enum
      end
    end
    
    class NilParentError < RuntimeError; end
    class UnmutableParentError < ArgumentError; end
  end
end
