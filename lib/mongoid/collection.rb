# encoding: utf-8
require "mongoid/collections/operations"
require "mongoid/collections/cyclic_iterator"
require "mongoid/collections/mimic"
require "mongoid/collections/master"
require "mongoid/collections/slaves"

module Mongoid #:nodoc
  class Collection
    include Collections::Mimic
    attr_reader :counter, :name

    # All write operations should delegate to the master connection. These
    # operations mimic the methods on a Mongo:Collection.
    #
    # Example:
    #
    # <tt>collection.save({ :name => "Al" })</tt>
    proxy(:master, Collections::Operations::WRITE)

    # All read operations should be intelligently directed to either the master
    # or the slave, depending on where the read counter is and what it's
    # maximum was configured at.
    #
    # Example:
    #
    # <tt>collection.find({ :name => "Al" })</tt>
    proxy(:directed, (Collections::Operations::READ - [:find]))

    # Determines where to send the next read query. If the slaves are not
    # defined then send to master. If the read counter is under the configured
    # maximum then return the master. In any other case return the slaves.
    #
    # Example:
    #
    # <tt>collection.directed</tt>
    #
    # Return:
    #
    # Either a +Master+ or +Slaves+ collection.
    def directed
      if under_max_counter? || slaves.empty?
        @counter = @counter + 1
        master
      else
        @counter = 0
        slaves
      end
    end

    # Find documents from the database given a selector and options.
    #
    # Options:
    #
    # selector: A +Hash+ selector that is the query.
    # options: The options to pass to the db.
    #
    # Example:
    #
    # <tt>collection.find({ :test => "value" })</tt>
    def find(selector = {}, options = {})
      cursor = Mongoid::Cursor.new(self, directed.find(selector, options))
      if block_given?
        yield cursor; cursor.close
      else
        cursor
      end
    end

    # Initialize a new Mongoid::Collection, setting up the master, slave, and
    # name attributes. Masters will be used for writes, slaves for reads.
    #
    # Example:
    #
    # <tt>Mongoid::Collection.new(masters, slaves, "test")</tt>
    def initialize(name)
      @name, @counter = name, 0
    end

    # Return the object responsible for reading documents from the database.
    # This is usually the slave databases, but in their absence the master will
    # handle the task.
    #
    # Example:
    #
    # <tt>collection.reader</tt>
    def slaves
      @slaves ||= Collections::Slaves.new(Mongoid.slaves, @name)
    end

    # Return the object responsible for writes to the database. This will
    # always return a collection associated with the Master DB.
    #
    # Example:
    #
    # <tt>collection.writer</tt>
    def master
      @master ||= Collections::Master.new(Mongoid.master, @name)
    end

    protected
    def under_max_counter?
      @counter < Mongoid.max_successive_reads
    end
  end
end
